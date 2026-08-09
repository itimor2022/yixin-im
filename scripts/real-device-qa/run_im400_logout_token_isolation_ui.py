#!/usr/bin/env python3
"""Validate token expiry and logout isolation on a local-backend Android device."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
import time
import uuid
from datetime import datetime
from pathlib import Path
from typing import Any

import uiautomator2 as u2


SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from run_im345_im357_single_device import app_notification_keys, run_adb  # noqa: E402
from run_im400_multidevice_session_ui import (  # noqa: E402
    api,
    check,
    click_label,
    is_main,
    login_ui,
    mysql,
    open_devices_page,
    redis,
    snapshot,
    wait_for,
)
from run_p1_fix_validation import find_private_chat, request_json  # noqa: E402


def latest_session(username: str) -> dict[str, str]:
    row = mysql(
        "SELECT u.id,u.uuid,s.id,s.device_id,s.token "
        "FROM user_sessions s JOIN users u ON u.id=s.user_id "
        f"WHERE u.username='{username}' AND s.device_name='HUAWEI ELS-AN00' "
        "ORDER BY s.id DESC LIMIT 1"
    )
    fields = row.split("\t")
    check(len(fields) == 5 and fields[4], f"active {username} device session missing: {row}")
    return {
        "user_id": fields[0],
        "user_uuid": fields[1],
        "session_id": fields[2],
        "device_id": fields[3],
        "token": fields[4],
    }


def assert_token_owner(base_url: str, token: str, username: str) -> None:
    payload = api(base_url, "GET", "/user/me", token=token).get("data", {})
    check(payload.get("username") == username, f"token does not belong to {username}")


def visible_login_error(device: u2.Device) -> bool:
    xml = device.dump_hierarchy()
    return "登录您的账号" in xml and "登录已过期，请重新登录" in xml


def click_dialog_logout(device: u2.Device) -> None:
    selectors = [device(text="退出登录"), device(description="退出登录")]
    for selector in selectors:
        if selector.count > 0:
            selector[selector.count - 1].click()
            return
    raise AssertionError("logout confirmation action missing")


def logout_from_devices_page(device: u2.Device, output_dir: Path) -> list[str]:
    evidence: list[str] = []
    check(click_label(device, "设置", timeout=2), "settings tab missing")
    time.sleep(1)
    open_devices_page(device)
    width, height = device.window_size()
    scrollable = device(scrollable=True)
    if scrollable.exists(timeout=1):
        try:
            scrollable.fling.toEnd(max_swipes=60)
            time.sleep(1)
        except Exception:  # noqa: BLE001 - fall back to deterministic swipes
            pass
    for _ in range(60):
        logout = device(text="退出登录")
        if logout.exists(timeout=0.3):
            bounds = logout.info.get("bounds", {})
            if 0 < int(bounds.get("top", 0)) < height:
                break
        device.swipe(width // 2, int(height * 0.82), width // 2, int(height * 0.25), 0.5)
        time.sleep(0.5)
    check(device(text="退出登录").exists(timeout=1), "logout tile missing")
    evidence += snapshot(device, output_dir, "im013-before-ui-logout")
    device(text="退出登录").click()
    wait_for(
        lambda: device(text="取消").exists(timeout=0.2),
        "logout confirmation dialog missing",
    )
    evidence += snapshot(device, output_dir, "im013-logout-confirmation")
    click_dialog_logout(device)
    wait_for(
        lambda: "登录您的账号" in device.dump_hierarchy(),
        "UI logout did not return to login",
        timeout=45,
    )
    evidence += snapshot(device, output_dir, "im013-after-ui-logout")
    return evidence


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--adb",
        default=str(Path.home() / "AppData/Local/Android/Sdk/platform-tools/adb.exe"),
    )
    parser.add_argument("--serial", default="8MY0220C17006781")
    parser.add_argument("--package", default="com.genericim.app")
    parser.add_argument("--base-url", default="http://127.0.0.1:8080/api/v1")
    parser.add_argument("--username", default="smoke_bob")
    parser.add_argument("--password", default="Smoke123")
    parser.add_argument("--sender-username", default="smoke_alice")
    parser.add_argument("--skip-token-expiry", action="store_true")
    parser.add_argument(
        "--output-dir",
        default="artifacts/real-device-qa/im400-round12-logout-token-isolation-ui",
    )
    args = parser.parse_args()

    output_dir = Path(args.output_dir).resolve() / datetime.now().strftime("%Y%m%d-%H%M%S")
    output_dir.mkdir(parents=True, exist_ok=True)
    device = u2.connect(args.serial)
    evidence: list[str] = []
    cases: list[dict[str, Any]] = []
    error = ""
    sent_token = ""
    sent_chat_id = ""
    sent_msg_id = ""

    run_adb(args.adb, args.serial, "reverse", "tcp:8080", "tcp:8080")
    run_adb(args.adb, args.serial, "logcat", "-c")
    try:
        check(is_main(device), "target device was not on the authenticated main UI")
        if not args.skip_token_expiry:
            session = latest_session(args.username)
            assert_token_owner(args.base_url, session["token"], args.username)
            revoked_hash = hashlib.sha256(session["token"].encode("utf-8")).hexdigest()
            revoked_key = f"user:token_revoked:{session['user_uuid']}:{revoked_hash}"
            redis("SET", revoked_key, "true", "EX", "604800")
            check(redis("EXISTS", revoked_key) == "1", "device token revocation key missing")

            device.app_start(args.package, stop=True, wait=True)
            wait_for(
                lambda: visible_login_error(device),
                "revoked token did not return to login with an expiry reason",
                timeout=45,
            )
            evidence += snapshot(device, output_dir, "im018-token-expired")
            time.sleep(5)
            check(visible_login_error(device), "token-expiry UI was not stable")
            cases.append(
                {
                    "case_id": "IM-018",
                    "status": "PASS",
                    "detail": (
                        "the real Huawei client rejected a server-revoked token, cleared local "
                        "authentication, stayed on login, and displayed the localized expiry reason"
                    ),
                }
            )

            evidence += login_ui(
                device,
                args.package,
                args.username,
                args.password,
                output_dir,
                "im018-restored",
                expect_notice=None,
            )
        restored = latest_session(args.username)
        assert_token_owner(args.base_url, restored["token"], args.username)

        fallback_token = f"round12-ui-hms-{uuid.uuid4().hex}"
        api(
            args.base_url,
            "POST",
            "/user/push-token",
            token=restored["token"],
            body={
                "device_id": restored["device_id"],
                "push_token": fallback_token,
                "device_type": "android",
                "push_channel": "hms",
                "brand": "HUAWEI",
                "model": "ELS-AN00",
                "device_name": "Round 12 UI fallback",
            },
        )
        stored = mysql(
            "SELECT push_token FROM user_devices "
            f"WHERE user_id={restored['user_id']} "
            f"AND device_id='{restored['device_id']}:push:hms'"
        )
        check(stored == fallback_token, "fallback-only HMS binding was not stored")

        baseline_keys = app_notification_keys(args.adb, args.serial, args.package)
        evidence += logout_from_devices_page(device, output_dir)
        residual = mysql(
            "SELECT COUNT(*) FROM user_devices "
            f"WHERE user_id={restored['user_id']} "
            f"AND (device_id='{restored['device_id']}' "
            f"OR device_id='{restored['device_id']}:voip' "
            f"OR device_id LIKE '{restored['device_id']}:push:%') "
            "AND (push_token<>'' OR push_token_hash IS NOT NULL "
            "OR push_token_updated_at IS NOT NULL)"
        )
        check(residual == "0", f"UI logout retained push binding fields: {residual}")

        sender = latest_session(args.sender_username)
        assert_token_owner(args.base_url, sender["token"], args.sender_username)
        sent_token = sender["token"]
        sent_chat_id = find_private_chat(
            args.base_url, sent_token, args.username
        )
        marker = f"IM013_LOGOUT_ISOLATION_{datetime.now().strftime('%H%M%S')}"
        client_msg_id = str(uuid.uuid4())
        response = request_json(
            args.base_url,
            "/message/send",
            sent_token,
            {
                "chat_id": sent_chat_id,
                "type": 1,
                "content": {"text": marker},
                "msg_id": client_msg_id,
            },
        )
        check(int(response.get("code", -1)) == 0, f"message send failed: {response}")
        sent_msg_id = str((response.get("data") or {}).get("msg_id") or client_msg_id)
        time.sleep(8)
        notification_dump = run_adb(
            args.adb,
            args.serial,
            "shell",
            "dumpsys",
            "notification",
            "--noredact",
        )
        notification_path = output_dir / "im013-notifications-after-send.txt"
        notification_path.write_text(notification_dump, encoding="utf-8")
        evidence.append(notification_path.as_posix())
        check(marker not in notification_dump, "logged-out account message leaked into notifications")
        check(
            app_notification_keys(args.adb, args.serial, args.package) == baseline_keys,
            "logged-out message created a new app notification",
        )
        check(
            "登录您的账号" in device.dump_hierarchy(),
            "logged-out device left the login page after an old-account message",
        )
        cases.append(
            {
                "case_id": "IM-013",
                "status": "PASS",
                "detail": (
                    "real-device UI logout cleared a server-only HMS binding; a unique message "
                    "sent afterward created no notification and the client remained signed out"
                ),
            }
        )
    except Exception as exc:  # noqa: BLE001
        error = f"{type(exc).__name__}: {exc}"
    finally:
        if sent_token and sent_chat_id and sent_msg_id:
            try:
                request_json(
                    args.base_url,
                    "/message/revoke",
                    sent_token,
                    {"chat_id": sent_chat_id, "msg_id": sent_msg_id},
                )
            except Exception as cleanup_error:  # noqa: BLE001
                error = error or f"message cleanup: {cleanup_error}"
        try:
            if not is_main(device):
                evidence += login_ui(
                    device,
                    args.package,
                    args.username,
                    args.password,
                    output_dir,
                    "im013-restored",
                    expect_notice=None,
                )
        except Exception as restore_error:  # noqa: BLE001
            error = error or f"restore: {restore_error}"

        logcat = run_adb(args.adb, args.serial, "logcat", "-d", "-v", "time")
        logcat_path = output_dir / "device-logcat.txt"
        logcat_path.write_text(logcat, encoding="utf-8")
        evidence.append(logcat_path.as_posix())
        fatal_lines = [
            line
            for line in logcat.splitlines()
            if "FATAL EXCEPTION" in line
            or f"ANR in {args.package}" in line
            or "FlutterError" in line
        ]
        if fatal_lines:
            error = error or f"fatal Android errors: {fatal_lines[:5]}"

    expected_case_count = 1 if args.skip_token_expiry else 2
    status = "PASS" if not error and len(cases) == expected_case_count else "FAIL"
    report = {
        "status": status,
        "cases": cases,
        "error": error,
        "device": args.serial,
        "backend": args.base_url,
        "evidence": evidence,
        "tested_at": datetime.now().astimezone().isoformat(timespec="seconds"),
    }
    result_path = output_dir / "results.json"
    result_path.write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(result_path)
    if error:
        print(error, file=sys.stderr)
    return 0 if status == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
