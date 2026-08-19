#!/usr/bin/env python3
"""Install one APK and log one or more real devices into the requested accounts."""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import time
from datetime import datetime
from pathlib import Path
from typing import Any

import uiautomator2 as u2


def run_adb(adb: str, serial: str, *args: str, timeout: int = 90) -> str:
    result = subprocess.run(
        [adb, "-s", serial, *args],
        check=False,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=timeout,
    )
    if result.returncode:
        raise RuntimeError(
            f"adb {serial} {' '.join(args)} failed: {result.stdout} {result.stderr}"
        )
    return result.stdout.strip()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest().upper()


def dismiss_permissions(device: u2.Device, seconds: int = 10) -> None:
    deadline = time.monotonic() + seconds
    labels = (
        "允许",
        "始终允许",
        "仅在使用中允许",
        "使用应用时允许",
        "确定",
        "继续",
    )
    while time.monotonic() < deadline:
        clicked = False
        for label in labels:
            if device(text=label).click_exists(timeout=0.2):
                clicked = True
                time.sleep(0.8)
                break
        if not clicked:
            break


def hierarchy(device: u2.Device, retries: int = 3) -> str:
    latest = ""
    for _ in range(retries):
        latest = device.dump_hierarchy()
        if "com.genericim.ma100" in latest:
            return latest
        time.sleep(1)
    return latest


def is_main(device: u2.Device) -> bool:
    xml = hierarchy(device)
    return "登录您的账号" not in xml and all(
        label in xml for label in ("消息", "联系人", "设置")
    )


def check_terms(device: u2.Device) -> None:
    width, height = device.window_size()
    for _ in range(3):
        checkbox = device(className="android.widget.CheckBox")
        if checkbox.exists:
            if not bool(checkbox.info.get("checked")):
                checkbox.click()
                time.sleep(0.5)
            return
        device.swipe(
            int(width * 0.5),
            int(height * 0.90),
            int(width * 0.5),
            int(height * 0.35),
            duration=0.6,
        )
        time.sleep(0.8)
    raise RuntimeError("login terms checkbox did not become visible after scrolling")


def submit_login(device: u2.Device) -> None:
    if device(description="登录").click_exists(timeout=1):
        return
    if device(text="登录").click_exists(timeout=1):
        return
    width, height = device.window_size()
    device.click(int(width * 0.5), int(height * 0.63))


def login_device(
    adb: str,
    serial: str,
    username: str,
    password: str,
    package: str,
    output_dir: Path,
) -> dict[str, Any]:
    device = u2.connect(serial)
    device.app_start(package, stop=True, wait=True)
    time.sleep(4)
    dismiss_permissions(device)

    for _ in range(3):
        if is_main(device):
            break
        edits = device(className="android.widget.EditText")
        if edits.count < 2:
            device.press("back")
            device.app_start(package, wait=True)
            time.sleep(3)
            dismiss_permissions(device)
            continue
        edits[0].click()
        edits[0].set_text(username)
        edits[1].click()
        edits[1].set_text(password)
        device.press("back")
        time.sleep(0.8)
        check_terms(device)
        submit_login(device)
        time.sleep(7)
        dismiss_permissions(device, seconds=12)

    xml = hierarchy(device)
    output_dir.mkdir(parents=True, exist_ok=True)
    (output_dir / f"{username}-final.xml").write_text(xml, encoding="utf-8")
    device.screenshot(str(output_dir / f"{username}-final.png"))
    main_ui = "登录您的账号" not in xml and all(
        label in xml for label in ("消息", "联系人", "设置")
    )
    if not main_ui:
        raise RuntimeError(f"{username} did not reach the main UI")

    package_dump = run_adb(adb, serial, "shell", "dumpsys", "package", package)
    installed_path = run_adb(adb, serial, "shell", "pm", "path", package).removeprefix(
        "package:"
    )
    installed_hash = run_adb(
        adb, serial, "shell", "sha256sum", installed_path
    ).split()[0].upper()
    return {
        "serial": serial,
        "username": username,
        "main_ui": True,
        "notifications_permission_granted": (
            "android.permission.POST_NOTIFICATIONS: granted=true" in package_dump
        ),
        "installed_sha256": installed_hash,
    }


def parse_device(value: str) -> tuple[str, str]:
    if "=" not in value:
        raise argparse.ArgumentTypeError("device must use SERIAL=USERNAME")
    serial, username = value.split("=", 1)
    if not serial or not username:
        raise argparse.ArgumentTypeError("device must use SERIAL=USERNAME")
    return serial, username


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--adb", required=True)
    parser.add_argument("--apk", required=True)
    parser.add_argument("--device", action="append", type=parse_device, required=True)
    parser.add_argument("--password", required=True)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--package", default="com.genericim.ma100")
    parser.add_argument("--skip-install", action="store_true")
    args = parser.parse_args()

    apk = Path(args.apk).resolve()
    if not apk.is_file():
        raise FileNotFoundError(apk)
    output_dir = Path(args.output_dir).resolve() / datetime.now().strftime(
        "%Y%m%d-%H%M%S"
    )
    expected_hash = sha256_file(apk)
    results: list[dict[str, Any]] = []

    for serial, username in args.device:
        if run_adb(args.adb, serial, "get-state") != "device":
            raise RuntimeError(f"device offline: {serial}")
        if not args.skip_install:
            install_output = run_adb(
                args.adb, serial, "install", "-r", str(apk), timeout=180
            )
            if "Success" not in install_output:
                raise RuntimeError(f"install failed for {serial}: {install_output}")
        run_adb(args.adb, serial, "shell", "pm", "clear", args.package)
        result = login_device(
            args.adb,
            serial,
            username,
            args.password,
            args.package,
            output_dir,
        )
        result["sha256_matches"] = result["installed_sha256"] == expected_hash
        if not result["sha256_matches"]:
            raise RuntimeError(f"installed APK hash mismatch: {serial}")
        results.append(result)

    payload = {
        "status": "PASS",
        "apk": str(apk),
        "apk_sha256": expected_hash,
        "results": results,
        "output_dir": str(output_dir),
    }
    (output_dir / "result.json").write_text(
        json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print(json.dumps(payload, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
