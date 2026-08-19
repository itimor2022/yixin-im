#!/usr/bin/env python3
"""Complete phone/SMS registration in the local Android emulator UI."""

from __future__ import annotations

import argparse
import json
import subprocess
import time
import urllib.request
from datetime import datetime
from pathlib import Path
from typing import Any

import uiautomator2 as u2


def check(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


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


def redis(*args: str) -> str:
    completed = subprocess.run(
        ["docker", "exec", "genericim-redis", "redis-cli", "--raw", *args],
        text=True,
        encoding="utf-8",
        errors="replace",
        capture_output=True,
        timeout=20,
        check=False,
    )
    if completed.returncode != 0:
        raise RuntimeError(f"redis-cli failed: {completed.stderr.strip()}")
    return completed.stdout.strip()


def registration_code(phone: str) -> str:
    raw = redis("GET", f"auth:register:sms:{phone}")
    try:
        decoded = json.loads(raw)
        code = decoded if isinstance(decoded, str) else raw
    except json.JSONDecodeError:
        code = raw
    check(len(code) == 6 and code.isdigit(), "registration code missing from local Redis")
    return code


def api_request(base_url: str, method: str, path: str, body: dict[str, Any]) -> dict[str, Any]:
    request = urllib.request.Request(
        f"{base_url.rstrip('/')}{path}",
        data=json.dumps(body).encode("utf-8"),
        headers={"Accept": "application/json", "Content-Type": "application/json"},
        method=method,
    )
    with urllib.request.urlopen(request, timeout=20) as response:
        payload = json.loads(response.read().decode("utf-8"))
    check(payload.get("code") == 0, f"API verification failed: {payload}")
    return payload


def wait_for(condition: Any, message: str, timeout: float = 15) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if condition():
            return
        time.sleep(0.25)
    raise AssertionError(message)


def dismiss_notification_permission(device: u2.Device) -> None:
    for selector in (
        device(resourceId="com.android.permissioncontroller:id/permission_deny_button"),
        device(text="Don’t allow"),
        device(text="不允许"),
    ):
        if selector.exists(timeout=1):
            selector.click()
            return


def snapshot(device: u2.Device, output_dir: Path, name: str) -> list[str]:
    png = output_dir / f"{name}.png"
    xml = output_dir / f"{name}.xml"
    device.screenshot(str(png))
    xml.write_text(device.dump_hierarchy(), encoding="utf-8")
    return [png.as_posix(), xml.as_posix()]


def fill_field(device: u2.Device, field: Any, value: str) -> None:
    field.click()
    time.sleep(0.2)
    device.send_keys(value, clear=True)
    time.sleep(0.2)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--adb", required=True)
    parser.add_argument("--device", default="emulator-5554")
    parser.add_argument("--package", default="com.genericim.ma100")
    parser.add_argument("--base-url", default="http://127.0.0.1:8080/api/v1")
    parser.add_argument(
        "--output-dir",
        default="artifacts/real-device-qa/registration-sms-ui",
    )
    args = parser.parse_args()

    run_id = str(int(time.time()))
    username = f"smsui{run_id[-10:]}"[:20]
    phone = f"19{int(run_id[-9:]) % 1_000_000_000:09d}"
    password = "QaSmsUI123"
    output_dir = Path(args.output_dir).resolve() / datetime.now().strftime("%Y%m%d-%H%M%S")
    output_dir.mkdir(parents=True, exist_ok=True)
    evidence: list[str] = []

    adb(args.adb, args.device, "shell", "pm", "clear", args.package)
    adb(args.adb, args.device, "reverse", "tcp:8080", "tcp:8080")
    adb(args.adb, args.device, "logcat", "-c")
    device = u2.connect(args.device)
    device.app_start(args.package, stop=True, wait=True)
    time.sleep(4)
    dismiss_notification_permission(device)

    register_link = device(description="立即注册")
    wait_for(lambda: register_link.exists, "registration link did not appear")
    register_link.click()
    wait_for(
        lambda: device(className="android.widget.EditText").count >= 5,
        "phone registration form did not appear",
    )
    evidence += snapshot(device, output_dir, "01-phone-registration-form")

    fields = device(className="android.widget.EditText")
    fill_field(device, fields[0], username)
    fill_field(device, fields[1], phone)
    time.sleep(1)
    device(description="获取验证码").click()
    wait_for(lambda: redis("EXISTS", f"auth:register:sms:{phone}") == "1", "SMS code was not created")
    code = registration_code(phone)
    fields = device(className="android.widget.EditText")
    fill_field(device, fields[2], code)
    fill_field(device, fields[3], password)
    fill_field(device, fields[4], password)
    evidence += snapshot(device, output_dir, "02-account-fields-complete")

    device.swipe(540, 1950, 540, 1150, duration=0.3)
    next_button = device(description="下一步")
    wait_for(lambda: next_button.exists, "next button did not appear")
    next_button.click()
    wait_for(
        lambda: device(description="完善资料").exists
        or device(description="完成注册").exists,
        "profile step did not appear",
    )

    profile_fields = device(className="android.widget.EditText")
    check(profile_fields.count >= 1, "nickname field missing")
    fill_field(device, profile_fields[0], f"SMS User {run_id[-4:]}")
    device.swipe(540, 1900, 540, 900, duration=0.4)
    checkbox = device(className="android.widget.CheckBox")
    wait_for(lambda: checkbox.exists, "agreement checkbox missing")
    if not checkbox.info.get("checked", False):
        checkbox.click()
    evidence += snapshot(device, output_dir, "03-profile-and-agreement")

    finish = device(description="完成注册")
    wait_for(lambda: finish.exists, "finish registration button missing")
    finish.click()
    wait_for(
        lambda: device(description="消息").exists
        or device(descriptionContains="消息").exists,
        "registration did not enter the authenticated home page",
        timeout=30,
    )
    evidence += snapshot(device, output_dir, "04-registration-success")

    login = api_request(
        args.base_url,
        "POST",
        "/auth/login",
        {
            "username": username,
            "password": password,
            "device_id": f"sms-ui-login-{run_id}",
            "device_type": "qa",
            "device_name": "SMS UI Login Verification",
        },
    ).get("data", {})
    check(str(login.get("token", "")) != "", "UI-created account cannot log in again")

    logcat = adb(args.adb, args.device, "logcat", "-d", "-t", "800")
    logcat_path = output_dir / "logcat.txt"
    logcat_path.write_text(logcat, encoding="utf-8")
    evidence.append(logcat_path.as_posix())
    fatal_markers = ["FATAL EXCEPTION", "ANR in com.genericim.ma100", "FlutterError"]
    check(not any(marker.lower() in logcat.lower() for marker in fatal_markers), "fatal log marker found")

    result = {
        "status": "PASS",
        "case_ids": ["IM-001"],
        "device": args.device,
        "detail": "phone and local SMS code registration completed in the Android UI, entered home, and logged in again",
        "evidence": evidence,
        "tested_at": datetime.now().astimezone().isoformat(timespec="seconds"),
    }
    result_path = output_dir / "results.json"
    result_path.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(result_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
