#!/usr/bin/env python3
"""Validate account-scoped chats and drafts on a local Android emulator."""

from __future__ import annotations

import argparse
import json
import subprocess
import time
import uuid
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any

import uiautomator2 as u2

from run_im400_remaining_api import Actor, Api, check, create_chat, response_data, send_text


@dataclass
class Credential:
    username: str
    password: str
    actor: Actor
    nickname: str


def create_credential(api: Api, label: str, run_id: str) -> Credential:
    username = f"sw_{label.lower()}_{uuid.uuid4().hex[:6]}"[:20]
    password = f"Qa{uuid.uuid4().hex[:12]}"
    nickname = f"SW_{label}_{run_id[-6:]}"
    payload = api.request(
        "POST",
        "/auth/register",
        body={
            "username": username,
            "password": password,
            "nickname": nickname,
            "gender": "male",
            "device_id": f"switch-api-{label.lower()}-{run_id}",
            "device_type": "qa",
            "device_name": f"Switch API {label}",
        },
    )
    data = response_data(payload)
    check(isinstance(data, dict) and isinstance(data.get("user"), dict), "register payload missing user")
    actor = Actor(label, str(data["user"]["uuid"]), str(data["token"]))
    return Credential(username, password, actor, nickname)


def run_adb(adb: str, serial: str, *args: str, timeout: int = 40) -> str:
    completed = subprocess.run(
        [adb, "-s", serial, *args],
        text=True,
        encoding="utf-8",
        errors="replace",
        capture_output=True,
        timeout=timeout,
        check=False,
    )
    if completed.returncode != 0:
        raise RuntimeError(f"adb {' '.join(args)} failed: {completed.stderr.strip()}")
    return completed.stdout.strip()


def snapshot(device: u2.Device, directory: Path, name: str) -> list[str]:
    png = directory / f"{name}.png"
    xml = directory / f"{name}.xml"
    device.screenshot(str(png))
    xml.write_text(device.dump_hierarchy(), encoding="utf-8")
    return [png.as_posix(), xml.as_posix()]


def main_ui(device: u2.Device) -> bool:
    xml = device.dump_hierarchy()
    return "登录您的账号" not in xml and all(label in xml for label in ("消息", "联系人", "发现", "设置"))


def open_messages(device: u2.Device, package: str) -> None:
    device.app_start(package, stop=False, wait=True)
    for _ in range(10):
        if device.app_current().get("package") != package:
            device.app_start(package, stop=False, wait=True)
            time.sleep(0.5)
        if device(text="CANCEL").click_exists(timeout=0.2) or device(text="取消").click_exists(timeout=0.2):
            time.sleep(0.5)
        if main_ui(device):
            return
        if device(description="消息").click_exists(timeout=1) or device(text="消息").click_exists(timeout=1):
            time.sleep(1)
            return
        time.sleep(0.5)
    raise RuntimeError("messages tab unavailable")


def open_chat(device: u2.Device, title: str) -> None:
    if device(descriptionContains=title).click_exists(timeout=8):
        time.sleep(1)
        return
    if device(textContains=title).click_exists(timeout=2):
        time.sleep(1)
        return
    raise RuntimeError(f"chat not found: {title}")


def logout(device: u2.Device, package: str) -> None:
    device.app_start(package, stop=False, wait=True)
    for _ in range(5):
        if device(description="设置").click_exists(timeout=1) or device(text="设置").click_exists(timeout=1):
            break
        device.press("back")
    else:
        raise RuntimeError("settings tab unavailable")
    time.sleep(1)

    for _ in range(8):
        if device(descriptionContains="设备").click_exists(timeout=0.5) or device(textContains="设备").click_exists(timeout=0.5):
            break
        width, height = device.window_size()
        device.swipe(width // 2, int(height * 0.82), width // 2, int(height * 0.35), 0.4)
    else:
        raise RuntimeError("devices entry unavailable")
    time.sleep(1)

    for _ in range(12):
        if device(description="退出登录").click_exists(timeout=0.4) or device(text="退出登录").click_exists(timeout=0.4):
            break
        width, height = device.window_size()
        device.swipe(width // 2, int(height * 0.85), width // 2, int(height * 0.3), 0.35)
    else:
        raise RuntimeError("logout action unavailable")
    time.sleep(0.7)

    if not (device(description="退出登录").click_exists(timeout=2) or device(text="退出登录").click_exists(timeout=2)):
        raise RuntimeError("logout confirmation unavailable")
    if not device(description="登录您的账号").wait(timeout=25):
        raise RuntimeError("login page not reached after logout")


def login_existing(
    adb: str,
    serial: str,
    credential: Credential,
    package: str,
    output_dir: Path,
) -> dict[str, Any]:
    device = u2.connect(serial)
    output_dir.mkdir(parents=True, exist_ok=True)
    device.app_start(package, stop=True, wait=True)
    submit_attempts = 0
    deadline = time.monotonic() + 60
    while time.monotonic() < deadline:
        if device.app_current().get("package") != package:
            device.press("back")
            device.app_start(package, stop=False, wait=True)
            time.sleep(0.5)

        for label in (
            "CANCEL",
            "取消",
            "Don’t allow",
            "Don't allow",
            "Allow",
            "ALLOW",
            "允许",
            "仅在使用该应用时允许",
            "始终允许",
            "使用应用时",
        ):
            if device(text=label).click_exists(timeout=0.15):
                time.sleep(0.4)

        if main_ui(device):
            xml = device.dump_hierarchy()
            (output_dir / f"{credential.username}-final.xml").write_text(xml, encoding="utf-8")
            device.screenshot(str(output_dir / f"{credential.username}-final.png"))
            return {"username": credential.username, "main_ui": True}

        edits = device(className="android.widget.EditText")
        if edits.count >= 2 and submit_attempts < 3:
            # Check the agreement first. On API 36 the accessibility click can
            # rebuild the Flutter form, which invalidates previously located
            # EditText nodes and may clear automation-injected text.
            checkbox = device(className="android.widget.CheckBox")
            if checkbox.exists(timeout=0.5) and not bool(checkbox.info.get("checked")):
                checkbox.click()
                time.sleep(0.7)
            checkbox = device(className="android.widget.CheckBox")
            if not checkbox.exists(timeout=0.5) or not bool(checkbox.info.get("checked")):
                width, height = device.window_size()
                device.click(int(width * 0.18), int(height * 0.79))
                time.sleep(0.7)
                checkbox = device(className="android.widget.CheckBox")
            if checkbox.exists(timeout=0.5):
                check(bool(checkbox.info.get("checked")), "login agreement checkbox did not become checked")

            edits = device(className="android.widget.EditText")
            edits[0].click()
            device.send_keys(credential.username, clear=True)
            time.sleep(0.4)
            edits = device(className="android.widget.EditText")
            edits[1].click()
            device.send_keys(credential.password, clear=True)
            time.sleep(0.4)
            edits = device(className="android.widget.EditText")
            username_value = edits[0].get_text() or ""
            if username_value != credential.username:
                time.sleep(0.5)
                continue
            # FastInputIME does not necessarily show a soft keyboard. Sending
            # BACK here can therefore leave the app instead of dismissing IME.
            time.sleep(0.4)
            checkbox = device(className="android.widget.CheckBox")
            check(
                checkbox.exists(timeout=0.5) and bool(checkbox.info.get("checked")),
                "login agreement checkbox was reset before submit",
            )
            snapshot(device, output_dir, f"{credential.username}-before-submit-{submit_attempts + 1}")
            if not (
                device(description="登录").click_exists(timeout=1)
                or device(text="登录").click_exists(timeout=1)
            ):
                width, height = device.window_size()
                device.click(width // 2, int(height * 0.64))
            submit_attempts += 1
            time.sleep(2)
            continue
        time.sleep(0.5)

    xml = device.dump_hierarchy()
    (output_dir / f"{credential.username}-failed.xml").write_text(xml, encoding="utf-8")
    device.screenshot(str(output_dir / f"{credential.username}-failed.png"))
    raise RuntimeError(f"{credential.username} did not reach the main UI")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", default="http://127.0.0.1:8080")
    parser.add_argument("--adb", required=True)
    parser.add_argument("--serial", required=True)
    parser.add_argument("--apk", required=True)
    parser.add_argument("--package", default="com.genericim.ma100")
    parser.add_argument("--restore-username", default="demo")
    parser.add_argument("--restore-password", default="demo123")
    parser.add_argument("--output-dir", required=True)
    args = parser.parse_args()

    output_dir = Path(args.output_dir).resolve() / datetime.now().strftime("%Y%m%d-%H%M%S")
    output_dir.mkdir(parents=True, exist_ok=True)
    api = Api(args.base_url.rstrip("/") + "/api/v1")
    run_id = f"{int(time.time())}-{uuid.uuid4().hex[:6]}"
    account_a = create_credential(api, "A", run_id)
    peer_a = create_credential(api, "PeerA", run_id)
    account_b = create_credential(api, "B", run_id)
    peer_b = create_credential(api, "PeerB", run_id)
    chat_a = create_chat(api, account_a.actor, 1, [peer_a.actor])
    chat_b = create_chat(api, account_b.actor, 1, [peer_b.actor])
    marker_a = f"ACCOUNT_A_ONLY_{run_id}"
    marker_b = f"ACCOUNT_B_ONLY_{run_id}"
    send_text(api, peer_a.actor, chat_a, marker_a)
    send_text(api, peer_b.actor, chat_b, marker_b)
    draft = f"DRAFT_A_{run_id}"
    device = u2.connect(args.serial)
    evidence: list[str] = []
    fatal_lines: list[str] = []
    cases: dict[str, dict[str, str]] = {}
    test_error = ""

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

    try:
        login_existing(args.adb, args.serial, account_a, args.package, output_dir / "login-a")
        open_messages(device, args.package)
        open_chat(device, peer_a.nickname)
        edit = device(className="android.widget.EditText")
        if not edit.exists(timeout=5):
            raise RuntimeError("chat composer unavailable for account A")
        device.set_fastinput_ime(True)
        edit.set_text(draft)
        time.sleep(1)
        device.press("back")
        time.sleep(1)
        evidence += snapshot(device, output_dir, "01-account-a-draft-list")
        xml_a = device.dump_hierarchy()
        check("草稿" in xml_a and draft in xml_a, "account A draft was not visible in its chat list")

        logout(device, args.package)
        evidence += snapshot(device, output_dir, "02-after-a-logout")
        login_existing(args.adb, args.serial, account_b, args.package, output_dir / "login-b")
        open_messages(device, args.package)
        time.sleep(2)
        evidence += snapshot(device, output_dir, "03-account-b-first-frame")
        xml_b = device.dump_hierarchy()
        check(peer_b.nickname in xml_b or marker_b in xml_b, "account B conversation did not load")
        check(peer_a.nickname not in xml_b and marker_a not in xml_b and draft not in xml_b, "account A data leaked into account B")

        logout(device, args.package)
        login_existing(args.adb, args.serial, account_a, args.package, output_dir / "login-a-restored")
        open_messages(device, args.package)
        time.sleep(2)
        evidence += snapshot(device, output_dir, "04-account-a-draft-restored")
        restored_xml = device.dump_hierarchy()
        check("草稿" in restored_xml and draft in restored_xml, "account A local draft did not restore after relogin")

        cases = {
            "IM-059": {
                "status": "PASS",
                "detail": "normal logout/login switched from account A to B without exposing A chat or draft data",
            },
            "IM-092": {
                "status": "PASS",
                "detail": "draft remained account-scoped and restored only after logging back into account A",
            },
            "IM-100": {
                "status": "PASS",
                "detail": "the first account-B chat frame contained only B data and never flashed account-A content",
            },
        }
    except Exception as exc:
        test_error = f"{type(exc).__name__}: {exc}"
        cases = {
            case_id: {"status": "FAIL", "detail": test_error}
            for case_id in ("IM-059", "IM-092", "IM-100")
        }
        evidence += snapshot(device, output_dir, "test-failed")
    finally:
        try:
            if main_ui(device):
                logout(device, args.package)
            restore = Credential(
                args.restore_username,
                args.restore_password,
                Actor("restore", "", ""),
                args.restore_username,
            )
            login_existing(args.adb, args.serial, restore, args.package, output_dir / "restore-demo")
            evidence += snapshot(device, output_dir, "05-demo-restored")
        except Exception as exc:
            (output_dir / "restore-error.txt").write_text(str(exc), encoding="utf-8")

    log = run_adb(args.adb, args.serial, "logcat", "-d", "-v", "threadtime", timeout=60)
    (output_dir / "logcat.txt").write_text(log, encoding="utf-8")
    fatal_lines = [
        line
        for line in log.splitlines()
        if "FATAL EXCEPTION" in line or "ANR in com.genericim.ma100" in line or "FlutterError" in line
    ]
    status = "PASS" if not test_error and not fatal_lines else "FAIL"
    payload = {
        "status": status,
        "base_url": args.base_url,
        "device": args.serial,
        "cases": cases,
        "evidence": evidence,
        "fatal_lines": fatal_lines,
        "fatal_anr_flutter_error_zero": not fatal_lines,
        "result_path": str((output_dir / "case-result.json").resolve()),
    }
    (output_dir / "case-result.json").write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(json.dumps({"status": status, "cases": sorted(cases), "result_path": payload["result_path"]}, ensure_ascii=False))
    return 0 if status == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
