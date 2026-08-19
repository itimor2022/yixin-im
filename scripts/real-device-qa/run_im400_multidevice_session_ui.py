#!/usr/bin/env python3
"""Validate multi-device notices and forced logout on Android devices."""

from __future__ import annotations

import argparse
import json
import subprocess
import time
import urllib.error
import urllib.request
from datetime import datetime
from pathlib import Path
from typing import Any

import uiautomator2 as u2


def check(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def adb(adb_path: str, serial: str, *args: str, allow_failure: bool = False, timeout: int = 120) -> str:
    completed = subprocess.run(
        [adb_path, "-s", serial, *args],
        text=True,
        encoding="utf-8",
        errors="replace",
        capture_output=True,
        timeout=timeout,
        check=False,
    )
    if completed.returncode != 0 and not allow_failure:
        raise RuntimeError(f"adb {serial} {' '.join(args)} failed: {completed.stderr.strip()}")
    return completed.stdout.strip()


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
    try:
        with urllib.request.urlopen(request, timeout=90) as response:
            payload = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
        raw = error.read().decode("utf-8", errors="replace")
        raise AssertionError(f"{method} {path} HTTP {error.code}: {raw}") from error
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
    output_dir.mkdir(parents=True, exist_ok=True)
    png = output_dir / f"{name}.png"
    xml = output_dir / f"{name}.xml"
    device.screenshot(str(png))
    xml.write_text(device.dump_hierarchy(), encoding="utf-8")
    return [png.as_posix(), xml.as_posix()]


def wait_for(condition: Any, message: str, timeout: float = 35) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if condition():
            return
        time.sleep(0.35)
    raise AssertionError(message)


def has_label(device: u2.Device, label: str, timeout: float = 0.2) -> bool:
    return device(description=label).exists(timeout=timeout) or device(text=label).exists(
        timeout=timeout
    )


def click_label(device: u2.Device, label: str, timeout: float = 1) -> bool:
    return device(description=label).click_exists(timeout=timeout) or device(
        text=label
    ).click_exists(timeout=timeout)


def dismiss_system_prompts(device: u2.Device, seconds: float = 8) -> None:
    deadline = time.monotonic() + seconds
    labels = (
        "允许",
        "仅在使用该应用时允许",
        "使用应用时允许",
        "始终允许",
        "确定",
        "继续",
        "CANCEL",
        "取消",
    )
    while time.monotonic() < deadline:
        clicked = False
        for label in labels:
            if device(text=label).click_exists(timeout=0.15):
                clicked = True
                time.sleep(0.5)
                break
        if not clicked:
            break


def is_main(device: u2.Device) -> bool:
    xml = device.dump_hierarchy()
    return "登录您的账号" not in xml and all(
        label in xml for label in ("消息", "联系人", "设置")
    )


def check_terms(device: u2.Device) -> None:
    width, height = device.window_size()
    for _ in range(7):
        checkbox = device(className="android.widget.CheckBox")
        if checkbox.exists(timeout=0.4):
            if bool(checkbox.info.get("checked")):
                return
            checkbox.click()
            time.sleep(0.7)
            checkbox = device(className="android.widget.CheckBox")
            if checkbox.exists(timeout=0.4) and bool(checkbox.info.get("checked")):
                return
            if checkbox.exists(timeout=0.4):
                bounds = checkbox.info.get("bounds", {})
                left = int(bounds.get("left", 0))
                right = int(bounds.get("right", 0))
                top = int(bounds.get("top", 0))
                bottom = int(bounds.get("bottom", 0))
                if right > left and bottom > top:
                    device.click((left + right) // 2, (top + bottom) // 2)
                    time.sleep(0.7)
                    checkbox = device(className="android.widget.CheckBox")
                    if checkbox.exists(timeout=0.4) and bool(checkbox.info.get("checked")):
                        return
        device.swipe(width // 2, int(height * 0.88), width // 2, int(height * 0.35), 0.5)
        time.sleep(0.5)
    raise AssertionError("agreement checkbox was not checked")


def scroll_to_login_fields(device: u2.Device) -> None:
    width, height = device.window_size()
    for _ in range(7):
        fields = device(className="android.widget.EditText")
        if fields.count >= 2:
            first_bounds = fields[0].info.get("bounds", {})
            if int(first_bounds.get("bottom", 0)) > 0:
                return
        device.swipe(width // 2, int(height * 0.35), width // 2, int(height * 0.88), 0.5)
        time.sleep(0.5)
    raise AssertionError("login fields did not return after checking agreement")


def submit_login(device: u2.Device) -> None:
    if device(description="登录").click_exists(timeout=1):
        return
    check(device(text="登录").click_exists(timeout=1), "login button missing")


def login_ui(
    device: u2.Device,
    package: str,
    username: str,
    password: str,
    output_dir: Path,
    label: str,
    *,
    expect_notice: bool | None,
) -> list[str]:
    evidence: list[str] = []
    device.app_start(package, stop=True, wait=True)
    dismiss_system_prompts(device)
    wait_for(
        lambda: device(className="android.widget.EditText").count >= 2,
        f"{label}: login fields missing",
    )
    device.set_input_ime(True)
    check_terms(device)
    scroll_to_login_fields(device)
    fields = device(className="android.widget.EditText")
    fields[0].click()
    device.send_keys(username, clear=True)
    fields = device(className="android.widget.EditText")
    fields[1].click()
    device.send_keys(password, clear=True)
    check(
        device(className="android.widget.EditText")[0].get_text() == username,
        f"{label}: username input failed",
    )
    evidence += snapshot(device, output_dir, f"{label}-before-login")
    submit_login(device)
    time.sleep(2)
    dismiss_system_prompts(device)

    if expect_notice is True:
        wait_for(
            lambda: has_label(device, "多端登录提醒"),
            f"{label}: multi-device notice missing",
        )
        xml = device.dump_hierarchy()
        check("允许多端共存" in xml and "设备管理" in xml, f"{label}: notice content incomplete")
        evidence += snapshot(device, output_dir, f"{label}-multi-device-notice")
        check(click_label(device, "我知道了", timeout=2), f"{label}: notice close action missing")
    elif expect_notice is False:
        time.sleep(1)
        check(not has_label(device, "多端登录提醒"), f"{label}: unexpected multi-device notice")
    elif has_label(device, "多端登录提醒", timeout=1):
        evidence += snapshot(device, output_dir, f"{label}-optional-multi-device-notice")
        click_label(device, "我知道了", timeout=1)

    wait_for(lambda: is_main(device), f"{label}: main UI not reached", timeout=45)
    evidence += snapshot(device, output_dir, f"{label}-main")
    return evidence


def open_devices_page(device: u2.Device) -> None:
    check(
        click_label(device, "设置", timeout=2),
        "settings tab missing",
    )
    time.sleep(1)
    width, height = device.window_size()
    for _ in range(8):
        if (
            device(descriptionContains="链接新设备").exists(timeout=0.2)
            or device(descriptionContains="活跃会话").exists(timeout=0.2)
            or device(descriptionContains="加密消息恢复").exists(timeout=0.2)
        ):
            return
        entry = device(descriptionStartsWith="设备")
        if entry.exists(timeout=0.4):
            bounds = entry.info.get("bounds", {})
            top = int(bounds.get("top", 0))
            bottom = int(bounds.get("bottom", 0))
            if bottom > int(height * 0.90) or top <= 0:
                device.swipe(
                    width // 2,
                    int(height * 0.82),
                    width // 2,
                    int(height * 0.38),
                    0.45,
                )
                time.sleep(0.6)
                continue
            entry.click()
            time.sleep(2)
            if (
                device(descriptionContains="链接新设备").exists(timeout=0.5)
                or device(descriptionContains="活跃会话").exists(timeout=0.5)
                or device(descriptionContains="加密消息恢复").exists(timeout=0.5)
            ):
                return
        if device(descriptionContains="设备管理").click_exists(timeout=0.5) or device(
            textContains="设备管理"
        ).click_exists(timeout=0.5):
            time.sleep(2)
            return
        device.swipe(width // 2, int(height * 0.82), width // 2, int(height * 0.32), 0.45)
        time.sleep(0.5)
    raise AssertionError("devices settings entry missing")


def terminate_other_device(device: u2.Device, target_name: str, output_dir: Path) -> list[str]:
    evidence = snapshot(device, output_dir, "actor-devices-before-terminate")
    stable_name = target_name.split()[-1]
    target = device(descriptionContains=stable_name)
    if not target.exists(timeout=1):
        target = device(textContains=stable_name)
    check(target.exists, f"target device row missing: {target_name}")
    target.click()
    wait_for(
        lambda: has_label(device, "终止设备会话"),
        "terminate confirmation missing",
    )
    evidence += snapshot(device, output_dir, "actor-terminate-confirm")
    check(click_label(device, "终止", timeout=2), "terminate confirm action missing")
    time.sleep(2)
    evidence += snapshot(device, output_dir, "actor-devices-after-terminate")
    return evidence


def create_fixture(base_url: str, run_id: str) -> tuple[str, str, str, int, str]:
    username = f"multui{run_id[-10:]}"[:20]
    password = "QaMultiUI123"
    phone = f"15{int(run_id[-8:]) % 1_000_000_000:09d}"
    code = f"{int(run_id) % 1_000_000:06d}"
    redis("SETEX", f"auth:register:sms:{phone}", "300", json.dumps(code))
    seed_device = f"round10-seed-{run_id}"
    data = api(
        base_url,
        "POST",
        "/auth/register",
        body={
            "username": username,
            "password": password,
            "nickname": f"Multi UI {run_id[-4:]}",
            "gender": "male",
            "phone": phone,
            "sms_code": code,
            "device_id": seed_device,
            "device_type": "qa",
            "device_name": "Round 10 Seed",
        },
    ).get("data", {})
    token = str(data.get("token", ""))
    user = data.get("user", {})
    user_id = int(user.get("id", 0))
    user_uuid = str(user.get("uuid", ""))
    check(token and user_id and user_uuid, "fixture registration failed")
    api(base_url, "POST", "/auth/logout", token=token)
    mysql(
        f"DELETE FROM user_devices WHERE user_id={user_id} AND device_id='{seed_device}'"
    )
    return username, password, token, user_id, user_uuid


def delete_fixture(base_url: str, username: str, password: str, user_uuid: str) -> None:
    data = api(
        base_url,
        "POST",
        "/auth/login",
        body={
            "username": username,
            "password": password,
            "device_id": f"round10-cleanup-{int(time.time())}",
            "device_type": "qa",
            "device_name": "Round 10 Cleanup",
        },
    ).get("data", {})
    token = str(data.get("token", ""))
    check(token, "fixture cleanup login failed")
    api(base_url, "POST", "/user/account/send-delete-code", token=token)
    code = read_code(f"verify:delete_account:{user_uuid}")
    api(base_url, "DELETE", f"/user/account?code={code}", token=token)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--adb", required=True)
    parser.add_argument("--apk", required=True)
    parser.add_argument("--target", default="emulator-5554")
    parser.add_argument("--actor", default="8MY0220C17006781")
    parser.add_argument("--smoke", default="UQG5T20915006269")
    parser.add_argument("--package", default="com.genericim.ma100")
    parser.add_argument("--base-url", default="http://127.0.0.1:8080/api/v1")
    parser.add_argument("--restore-username", default="smoke_alice")
    parser.add_argument("--restore-password", default="Smoke123")
    parser.add_argument("--output-dir", default="artifacts/real-device-qa/multidevice-session-ui")
    args = parser.parse_args()

    run_id = str(int(time.time()))
    output_dir = Path(args.output_dir).resolve() / datetime.now().strftime("%Y%m%d-%H%M%S")
    output_dir.mkdir(parents=True, exist_ok=True)
    apk = str(Path(args.apk).resolve())
    evidence: list[str] = []
    username = ""
    password = ""
    user_uuid = ""
    cases: list[dict[str, Any]] = []
    error = ""

    try:
        username, password, _, user_id, user_uuid = create_fixture(args.base_url, run_id)
        for serial in (args.target, args.actor, args.smoke):
            check(adb(args.adb, serial, "get-state") == "device", f"device offline: {serial}")
            install = adb(args.adb, serial, "install", "-r", apk, timeout=240)
            check("Success" in install, f"APK install failed on {serial}: {install}")
            adb(args.adb, serial, "logcat", "-c")

        for serial in (args.target, args.actor):
            adb(args.adb, serial, "shell", "pm", "clear", args.package)
            adb(
                args.adb,
                serial,
                "shell",
                "pm",
                "grant",
                args.package,
                "android.permission.POST_NOTIFICATIONS",
                allow_failure=True,
            )

        target = u2.connect(args.target)
        actor = u2.connect(args.actor)
        evidence += login_ui(
            target,
            args.package,
            username,
            password,
            output_dir,
            "target-first-login",
            expect_notice=False,
        )
        evidence += login_ui(
            actor,
            args.package,
            username,
            password,
            output_dir,
            "actor-second-login",
            expect_notice=True,
        )
        cases.append(
            {
                "case_ids": ["IM-021"],
                "status": "PASS",
                "detail": "the second Android device received a one-time coexistence notice with the other active-device count and device-management guidance",
            }
        )

        rows = mysql(
            f"SELECT device_id, device_name FROM user_sessions WHERE user_id={user_id} ORDER BY last_active ASC"
        ).splitlines()
        check(len(rows) == 2, f"unexpected fixture devices: {rows}")
        target_name = rows[0].split("\t", 1)[1]
        open_devices_page(actor)
        evidence += terminate_other_device(actor, target_name, output_dir)

        wait_for(
            lambda: "登录您的账号" in target.dump_hierarchy()
            and "下线" in target.dump_hierarchy()
            and "重新登录" in target.dump_hierarchy(),
            "target device did not show the forced-logout reason",
            timeout=45,
        )
        forced_xml = target.dump_hierarchy()
        check("如非本人操作" in forced_xml, "forced-logout security guidance missing")
        evidence += snapshot(target, output_dir, "target-forced-logout-message")
        cases.append(
            {
                "case_ids": ["IM-025"],
                "status": "PASS",
                "detail": "the terminated device stopped its session and returned to login with actor device, server time, reason, and password-change guidance",
            }
        )

        evidence += login_ui(
            target,
            args.package,
            username,
            password,
            output_dir,
            "target-relogin",
            expect_notice=True,
        )
        cases.append(
            {
                "case_ids": ["IM-026"],
                "status": "PASS",
                "detail": "the terminated device authenticated again with a fresh token, displayed the coexistence notice, and reached the main UI",
            }
        )

        for serial in (args.target, args.actor):
            fatal = adb(
                args.adb,
                serial,
                "logcat",
                "-d",
                "-v",
                "brief",
                allow_failure=True,
            )
            fatal_lines = [
                line
                for line in fatal.splitlines()
                if "FATAL EXCEPTION" in line or "ANR in com.genericim.ma100" in line
            ]
            check(not fatal_lines, f"fatal Android errors on {serial}: {fatal_lines[:5]}")

        adb(args.adb, args.smoke, "shell", "monkey", "-p", args.package, "1", allow_failure=True)
        time.sleep(2)
    except Exception as exc:  # noqa: BLE001
        error = f"{type(exc).__name__}: {exc}"
    finally:
        if username and password and user_uuid:
            try:
                delete_fixture(args.base_url, username, password, user_uuid)
            except Exception as cleanup_error:  # noqa: BLE001
                error = error or f"cleanup: {cleanup_error}"
        try:
            adb(args.adb, args.actor, "shell", "pm", "clear", args.package)
            actor = u2.connect(args.actor)
            evidence += login_ui(
                actor,
                args.package,
                args.restore_username,
                args.restore_password,
                output_dir,
                "actor-restored",
                expect_notice=None,
            )
        except Exception as restore_error:  # noqa: BLE001
            error = error or f"restore: {restore_error}"
        adb(args.adb, args.target, "shell", "pm", "clear", args.package, allow_failure=True)

    status = "PASS" if not error and len(cases) == 3 else "FAIL"
    report = {
        "status": status,
        "cases": cases,
        "error": error,
        "devices": {"target": args.target, "actor": args.actor, "smoke": args.smoke},
        "apk": apk,
        "evidence": evidence,
        "tested_at": datetime.now().astimezone().isoformat(timespec="seconds"),
    }
    result_path = output_dir / "results.json"
    result_path.write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(result_path)
    if error:
        print(error)
    return 0 if status == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
