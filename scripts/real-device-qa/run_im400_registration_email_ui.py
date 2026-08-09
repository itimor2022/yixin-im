#!/usr/bin/env python3
"""Complete email verification registration in the local Android emulator UI."""

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


def adb(adb_path: str, serial: str, *args: str, allow_failure: bool = False) -> str:
    completed = subprocess.run(
        [adb_path, "-s", serial, *args],
        text=True,
        encoding="utf-8",
        errors="replace",
        capture_output=True,
        timeout=40,
        check=False,
    )
    if completed.returncode != 0 and not allow_failure:
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


def registration_code(email: str) -> str:
    raw = redis("GET", f"auth:register:email:{email.lower()}")
    try:
        decoded = json.loads(raw)
        code = decoded if isinstance(decoded, str) else raw
    except json.JSONDecodeError:
        code = raw
    check(len(code) == 6 and code.isdigit(), "email registration code missing from Redis")
    return code


def api_request(base_url: str, path: str, body: dict[str, Any]) -> dict[str, Any]:
    request = urllib.request.Request(
        f"{base_url.rstrip('/')}{path}",
        data=json.dumps(body).encode("utf-8"),
        headers={"Accept": "application/json", "Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=20) as response:
        payload = json.loads(response.read().decode("utf-8"))
    check(payload.get("code") == 0, f"API verification failed: {payload}")
    return payload


def wait_for(condition: Any, message: str, timeout: float = 20) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if condition():
            return
        time.sleep(0.25)
    raise AssertionError(message)


def first_existing(device: u2.Device, labels: tuple[str, ...]) -> Any:
    for label in labels:
        for selector in (
            device(description=label),
            device(text=label),
            device(descriptionContains=label),
            device(textContains=label),
        ):
            if selector.exists(timeout=0.2):
                return selector
    return None


def snapshot(device: u2.Device, output_dir: Path, name: str) -> list[str]:
    png = output_dir / f"{name}.png"
    xml = output_dir / f"{name}.xml"
    device.screenshot(str(png))
    xml.write_text(device.dump_hierarchy(), encoding="utf-8")
    return [png.as_posix(), xml.as_posix()]


def fill_field(
    device: u2.Device, field: Any, value: str, *, verify_text: bool = True
) -> None:
    field.click()
    time.sleep(0.2)
    try:
        field.set_text(value)
    except Exception:
        device.send_keys(value, clear=False)
    time.sleep(0.3)
    if verify_text and field.info.get("text", "") != value:
        field.click()
        device.shell(["input", "text", value.replace(" ", "%s")])
        time.sleep(0.3)
    if verify_text:
        check(
            field.info.get("text", "") == value,
            f"field input did not persist for {value!r}",
        )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--adb", required=True)
    parser.add_argument("--device", default="emulator-5554")
    parser.add_argument("--package", default="com.genericim.app")
    parser.add_argument("--base-url", default="http://127.0.0.1:8080/api/v1")
    parser.add_argument(
        "--output-dir", default="artifacts/real-device-qa/registration-email-ui"
    )
    args = parser.parse_args()

    run_id = str(int(time.time()))
    username = f"emailui{run_id[-9:]}"[:20]
    email = f"im400.email.ui.{run_id}@example.test"
    password = "QaEmailUI123"
    output_dir = Path(args.output_dir).resolve() / datetime.now().strftime("%Y%m%d-%H%M%S")
    output_dir.mkdir(parents=True, exist_ok=True)
    evidence: list[str] = []

    adb(args.adb, args.device, "shell", "pm", "clear", args.package)
    adb(args.adb, args.device, "reverse", "tcp:8080", "tcp:8080")
    adb(
        args.adb,
        args.device,
        "shell",
        "pm",
        "grant",
        args.package,
        "android.permission.POST_NOTIFICATIONS",
        allow_failure=True,
    )
    adb(args.adb, args.device, "logcat", "-c")
    device = u2.connect(args.device)
    device.app_start(args.package, stop=True, wait=True)
    time.sleep(4)

    register_link = first_existing(device, ("立即注册", "Register Now"))
    check(register_link is not None, "registration link did not appear")
    register_link.click()
    wait_for(
        lambda: first_existing(device, ("邮箱", "Email")) is not None,
        "email registration selector did not appear",
    )
    email_selector = first_existing(device, ("邮箱", "Email"))
    check(email_selector is not None, "email registration selector missing")
    email_selector.click()
    wait_for(
        lambda: "邮箱地址" in device.dump_hierarchy()
        or "Email address" in device.dump_hierarchy(),
        "email registration fields did not appear",
    )
    evidence += snapshot(device, output_dir, "01-email-registration-form")

    fields = device(className="android.widget.EditText")
    check(fields.count >= 5, f"expected five account fields, got {fields.count}")
    fill_field(device, fields[0], username)
    fill_field(device, fields[1], email)
    send_button = first_existing(device, ("获取验证码", "Send code"))
    check(send_button is not None, "send email code button missing")
    send_button.click()
    wait_for(
        lambda: redis("EXISTS", f"auth:register:email:{email}") == "1",
        "email code was not created",
    )
    code = registration_code(email)
    fields = device(className="android.widget.EditText")
    fill_field(device, fields[2], code)
    fill_field(device, fields[3], password, verify_text=False)
    fill_field(device, fields[4], password, verify_text=False)

    device.swipe(540, 1950, 540, 1050, duration=0.3)
    next_button = first_existing(device, ("下一步", "Next"))
    check(next_button is not None, "next button did not appear")
    next_button.click()
    wait_for(
        lambda: first_existing(device, ("完善资料", "Complete Profile")) is not None,
        "profile step did not appear",
    )
    wait_for(
        lambda: device(className="android.widget.EditText").count == 2,
        "profile form did not finish its transition",
    )

    profile_fields = device(className="android.widget.EditText")
    check(profile_fields.count == 2, "nickname and invite fields were not stable")
    nickname = f"Email User {run_id[-4:]}"
    fill_field(device, profile_fields[0], nickname)
    device.swipe(540, 1900, 540, 850, duration=0.4)
    checkbox = device(className="android.widget.CheckBox")
    wait_for(lambda: checkbox.exists, "agreement checkbox missing")
    if not checkbox.info.get("checked", False):
        checkbox.click()
    evidence += snapshot(device, output_dir, "03-profile-and-agreement")

    finish = first_existing(device, ("完成注册", "Finish Registration"))
    check(finish is not None, "finish registration button missing")
    finish.click()
    wait_for(
        lambda: first_existing(device, ("消息", "Messages")) is not None,
        "email registration did not enter the home page",
        timeout=30,
    )
    evidence += snapshot(device, output_dir, "04-email-registration-success")

    login = api_request(
        args.base_url,
        "/auth/login",
        {
            "username": username,
            "password": password,
            "device_id": f"email-ui-login-{run_id}",
            "device_type": "qa",
            "device_name": "Email UI Login Verification",
        },
    ).get("data", {})
    check(str(login.get("token", "")), "UI-created email account cannot log in again")
    check(login.get("user", {}).get("email") == email, "UI-created account lost its email")

    logcat = adb(args.adb, args.device, "logcat", "-d", "-t", "800")
    logcat_path = output_dir / "logcat.txt"
    logcat_path.write_text(logcat, encoding="utf-8")
    evidence.append(logcat_path.as_posix())
    fatal_markers = ("FATAL EXCEPTION", "ANR in com.genericim.app", "FlutterError")
    check(
        not any(marker.lower() in logcat.lower() for marker in fatal_markers),
        "fatal log marker found",
    )

    result = {
        "status": "PASS",
        "case_ids": ["IM-002"],
        "device": args.device,
        "detail": "email verification registration completed in the Android UI, entered home, persisted email, and logged in again",
        "evidence": evidence,
        "tested_at": datetime.now().astimezone().isoformat(timespec="seconds"),
    }
    result_path = output_dir / "results.json"
    result_path.write_text(
        json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(result_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
