#!/usr/bin/env python3
"""Verify the banned-account login dialog on the local Android emulator."""

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
        timeout=60,
        check=False,
    )
    if completed.returncode != 0 and not allow_failure:
        raise RuntimeError(f"adb {' '.join(args)} failed: {completed.stderr.strip()}")
    return completed.stdout


def api(
    base_url: str,
    method: str,
    path: str,
    *,
    body: dict[str, Any] | None = None,
    token: str | None = None,
) -> dict[str, Any]:
    headers = {"Accept": "application/json"}
    data = None if body is None else json.dumps(body).encode("utf-8")
    if body is not None:
        headers["Content-Type"] = "application/json"
    if token:
        headers["Authorization"] = f"Bearer {token}"
    request = urllib.request.Request(
        f"{base_url.rstrip('/')}{path}", data=data, headers=headers, method=method
    )
    with urllib.request.urlopen(request, timeout=90) as response:
        payload = json.loads(response.read().decode("utf-8"))
    check(payload.get("code") == 0, f"{method} {path} failed: {payload}")
    return payload


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
        raise RuntimeError(completed.stderr.strip())
    return completed.stdout.strip()


def mysql(sql: str) -> str:
    command = 'mysql -N -B -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" -e "$QA_SQL"'
    completed = subprocess.run(
        ["docker", "exec", "-e", f"QA_SQL={sql}", "genericim-mysql", "sh", "-lc", command],
        text=True,
        encoding="utf-8",
        errors="replace",
        capture_output=True,
        timeout=30,
        check=False,
    )
    if completed.returncode != 0:
        raise RuntimeError(completed.stderr.strip())
    return completed.stdout.strip()


def read_code(key: str) -> str:
    raw = redis("GET", key)
    try:
        decoded = json.loads(raw)
        code = decoded if isinstance(decoded, str) else raw
    except json.JSONDecodeError:
        code = raw
    check(len(code) == 6 and code.isdigit(), f"verification code missing for {key}")
    return code


def snapshot(device: u2.Device, output_dir: Path, name: str) -> list[str]:
    png = output_dir / f"{name}.png"
    xml = output_dir / f"{name}.xml"
    device.screenshot(str(png))
    xml.write_text(device.dump_hierarchy(), encoding="utf-8")
    return [png.as_posix(), xml.as_posix()]


def wait_for(condition: Any, message: str, timeout: float = 20) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if condition():
            return
        time.sleep(0.25)
    raise AssertionError(message)


def create_fixture(base_url: str, run_id: str) -> tuple[str, str, str, int, str]:
    username = f"banui{run_id[-10:]}"[:20]
    password = "QaBannedUI123"
    phone = f"17{int(run_id[-8:]) % 1_000_000_000:09d}"
    api(base_url, "POST", "/auth/register/send-code", body={"phone": phone})
    code = read_code(f"auth:register:sms:{phone}")
    data = api(
        base_url,
        "POST",
        "/auth/register",
        body={
            "username": username,
            "password": password,
            "nickname": f"Banned UI {run_id[-4:]}",
            "gender": "female",
            "phone": phone,
            "sms_code": code,
            "device_id": f"banned-ui-fixture-{run_id}",
            "device_type": "qa",
            "device_name": "Banned UI Fixture",
        },
    ).get("data", {})
    user = data.get("user", {})
    return username, password, str(data["token"]), int(user["id"]), str(user["uuid"])


def cleanup_fixture(base_url: str, token: str, user_uuid: str) -> None:
    api(base_url, "POST", "/user/account/send-delete-code", token=token)
    code = read_code(f"verify:delete_account:{user_uuid}")
    api(base_url, "DELETE", f"/user/account?code={code}", token=token)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--adb", required=True)
    parser.add_argument("--device", default="emulator-5554")
    parser.add_argument("--package", default="com.genericim.app")
    parser.add_argument("--base-url", default="http://127.0.0.1:8080/api/v1")
    parser.add_argument(
        "--output-dir", default="artifacts/real-device-qa/banned-login-ui"
    )
    args = parser.parse_args()

    run_id = str(int(time.time()))
    reason = "IM-017 UI appeal verification"
    output_dir = Path(args.output_dir).resolve() / datetime.now().strftime("%Y%m%d-%H%M%S")
    output_dir.mkdir(parents=True, exist_ok=True)
    evidence: list[str] = []
    token = ""
    user_uuid = ""

    try:
        username, password, token, user_id, user_uuid = create_fixture(args.base_url, run_id)
        mysql(
            f"UPDATE users SET status=3, ban_reason='{reason}', banned_at=NOW(), "
            f"updated_at=NOW() WHERE id={user_id} LIMIT 1"
        )

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
        wait_for(
            lambda: device(className="android.widget.EditText").count >= 2,
            "login fields did not appear",
        )

        checkbox = device(className="android.widget.CheckBox")
        if checkbox.exists and not bool(checkbox.info.get("checked")):
            checkbox.click()
            time.sleep(0.5)
        check(bool(device(className="android.widget.CheckBox").info.get("checked")), "agreement was not checked")

        device.set_input_ime(True)
        fields = device(className="android.widget.EditText")
        fields[0].click()
        device.send_keys(username, clear=True)
        fields = device(className="android.widget.EditText")
        fields[1].click()
        device.send_keys(password, clear=True)
        time.sleep(0.5)
        check(device(className="android.widget.EditText")[0].get_text() == username, "username input failed")

        login_button = device(description="登录")
        if not login_button.exists:
            login_button = device(text="登录")
        check(login_button.exists, "login button missing")
        login_button.click()

        wait_for(
            lambda: device(description="账号已被封禁").exists
            or device(text="账号已被封禁").exists,
            "banned-account dialog did not appear",
            timeout=30,
        )
        hierarchy = device.dump_hierarchy()
        for expected in (reason, "期限：永久", "联系客服申诉"):
            check(expected in hierarchy, f"banned dialog missing {expected!r}")
        check("消息" not in hierarchy, "banned account entered the authenticated home page")
        evidence += snapshot(device, output_dir, "01-banned-login-dialog")

        logcat = adb(args.adb, args.device, "logcat", "-d", "-t", "800")
        logcat_path = output_dir / "logcat.txt"
        logcat_path.write_text(logcat, encoding="utf-8")
        evidence.append(logcat_path.as_posix())
        fatal = [
            line
            for line in logcat.splitlines()
            if "FATAL EXCEPTION" in line
            or "ANR in com.genericim.app" in line
            or "FlutterError" in line
        ]
        check(not fatal, f"fatal log markers found: {fatal[:3]}")
    finally:
        if token and user_uuid:
            try:
                cleanup_fixture(args.base_url, token, user_uuid)
            except Exception as error:
                (output_dir / "cleanup-error.txt").write_text(str(error), encoding="utf-8")

    result = {
        "status": "PASS",
        "case_ids": ["IM-017"],
        "device": args.device,
        "detail": "banned login remained on the login screen and displayed reason, permanent duration and a contact-support appeal action",
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
