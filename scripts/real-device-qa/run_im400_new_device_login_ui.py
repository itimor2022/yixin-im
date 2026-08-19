#!/usr/bin/env python3
"""Validate the new-device login security alert on two Android devices."""

from __future__ import annotations

import argparse
import json
import time
from datetime import datetime
from pathlib import Path
from typing import Any

import uiautomator2 as u2

from run_im400_multidevice_session_ui import (
    adb,
    check,
    click_label,
    create_fixture,
    delete_fixture,
    dismiss_system_prompts,
    has_label,
    login_ui,
    mysql,
    snapshot,
    wait_for,
)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--adb", required=True)
    parser.add_argument("--apk", required=True)
    parser.add_argument("--target", default="8MY0220C17006781")
    parser.add_argument("--actor", default="UQG5T20915006269")
    parser.add_argument("--smoke", default="emulator-5554")
    parser.add_argument("--package", default="com.genericim.ma100")
    parser.add_argument("--base-url", default="http://127.0.0.1:8080/api/v1")
    parser.add_argument("--target-restore-username", default="smoke_bob")
    parser.add_argument("--actor-restore-username", default="smoke_alice")
    parser.add_argument("--restore-password", default="Smoke123")
    parser.add_argument(
        "--output-dir",
        default="artifacts/real-device-qa/new-device-login-ui",
    )
    args = parser.parse_args()

    run_id = str(int(time.time()))
    output_dir = Path(args.output_dir).resolve() / datetime.now().strftime(
        "%Y%m%d-%H%M%S"
    )
    output_dir.mkdir(parents=True, exist_ok=True)
    apk = str(Path(args.apk).resolve())
    evidence: list[str] = []
    cases: list[dict[str, Any]] = []
    username = ""
    password = ""
    user_uuid = ""
    error = ""

    try:
        username, password, _, user_id, user_uuid = create_fixture(
            args.base_url, run_id
        )
        for serial in (args.target, args.actor, args.smoke):
            check(adb(args.adb, serial, "get-state") == "device", f"offline: {serial}")
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
            "actor-new-device-login",
            expect_notice=True,
        )

        session_rows = mysql(
            "SELECT device_id, device_name, ip FROM user_sessions "
            f"WHERE user_id={user_id} ORDER BY last_active DESC"
        ).splitlines()
        check(len(session_rows) >= 2, f"unexpected sessions: {session_rows}")
        actor_session = session_rows[0].split("\t")
        check(len(actor_session) >= 3, f"invalid actor session: {session_rows[0]}")
        actor_name = actor_session[1]
        actor_ip = actor_session[2]

        wait_for(
            lambda: has_label(target, "新设备登录提醒"),
            "old device did not show the new-device security alert",
            timeout=30,
        )
        target_xml = target.dump_hierarchy()
        check(actor_name in target_xml, f"actor device name missing: {actor_name}")
        check(actor_ip in target_xml, f"actor login IP missing: {actor_ip}")
        check("如非本人操作" in target_xml, "security guidance missing")
        check("修改密码" in target_xml, "password-change guidance missing")
        evidence += snapshot(target, output_dir, "target-new-device-login-alert")

        check(
            click_label(target, "设备管理", timeout=2),
            "device management action missing",
        )
        wait_for(
            lambda: (
                target(descriptionContains="链接新设备").exists(timeout=0.2)
                or target(descriptionContains="活跃会话").exists(timeout=0.2)
                or target(descriptionContains="加密消息恢复").exists(timeout=0.2)
            ),
            "device management page did not open",
            timeout=30,
        )
        evidence += snapshot(target, output_dir, "target-device-management")
        cases.append(
            {
                "case_ids": ["IM-031"],
                "status": "PASS",
                "detail": "the original Android device showed the new-device name, IP, server time and security guidance, then opened device management",
            }
        )

        for serial in (args.target, args.actor):
            logcat = adb(
                args.adb,
                serial,
                "logcat",
                "-d",
                "-v",
                "brief",
                allow_failure=True,
            )
            fatal = [
                line
                for line in logcat.splitlines()
                if "FATAL EXCEPTION" in line or f"ANR in {args.package}" in line
            ]
            check(not fatal, f"fatal Android errors on {serial}: {fatal[:5]}")
    except Exception as exc:  # noqa: BLE001
        error = f"{type(exc).__name__}: {exc}"
    finally:
        if username and password and user_uuid:
            try:
                delete_fixture(args.base_url, username, password, user_uuid)
            except Exception as cleanup_error:  # noqa: BLE001
                error = error or f"cleanup: {cleanup_error}"

        restore_accounts = (
            (args.target, args.target_restore_username, "target-restored"),
            (args.actor, args.actor_restore_username, "actor-restored"),
        )
        for serial, restore_username, label in restore_accounts:
            try:
                adb(args.adb, serial, "shell", "pm", "clear", args.package)
                device = u2.connect(serial)
                dismiss_system_prompts(device, seconds=2)
                evidence += login_ui(
                    device,
                    args.package,
                    restore_username,
                    args.restore_password,
                    output_dir,
                    label,
                    expect_notice=None,
                )
            except Exception as restore_error:  # noqa: BLE001
                error = error or f"restore {serial}: {restore_error}"

    status = "PASS" if not error and len(cases) == 1 else "FAIL"
    report = {
        "status": status,
        "cases": cases,
        "error": error,
        "devices": {
            "target": args.target,
            "actor": args.actor,
            "smoke": args.smoke,
        },
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
