#!/usr/bin/env python3
"""Dual-device validation for file opening and recall edge cases."""

from __future__ import annotations

import argparse
import html
import json
import re
import shutil
import subprocess
import sys
import time
import uuid
from datetime import datetime
from pathlib import Path
from typing import Any

import requests


SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from run_im400_full import rel  # noqa: E402
from run_p1_fix_validation import (  # noqa: E402
    P1Harness,
    find_private_chat,
    list_messages,
    request_json,
)


def wait_until(predicate, timeout: float, interval: float = 0.35) -> bool:
    deadline = time.time() + timeout
    while time.time() < deadline:
        if predicate():
            return True
        time.sleep(interval)
    return False


def node_containing(harness: P1Harness, value: str) -> dict[str, Any] | None:
    matches = [
        item
        for item in harness.nodes()
        if value in html.unescape(f"{item['desc']} {item['text']}")
        and item["bottom"] > item["top"]
    ]
    if not matches:
        return None
    return max(
        matches,
        key=lambda item: (
            int(item["clickable"]),
            (item["right"] - item["left"]) * (item["bottom"] - item["top"]),
        ),
    )


def tap_node(harness: P1Harness, node: dict[str, Any]) -> None:
    harness.device.click(
        (node["left"] + node["right"]) // 2,
        (node["top"] + node["bottom"]) // 2,
    )


def long_press_node(harness: P1Harness, node: dict[str, Any]) -> None:
    harness.device.long_click(
        (node["left"] + node["right"]) // 2,
        (node["top"] + node["bottom"]) // 2,
        duration=1.0,
    )


def api_send(base: str, token: str, payload: dict[str, Any]) -> dict[str, Any]:
    response = requests.post(
        f"{base.rstrip('/')}/message/send",
        headers={"Authorization": f"Bearer {token}"},
        json=payload,
        timeout=45,
    )
    response.raise_for_status()
    body = response.json()
    if int(body.get("code", -1)) != 0:
        raise RuntimeError(f"message send failed: {body.get('message')}")
    return body.get("data") or {}


def api_upload(base: str, token: str, path: Path) -> dict[str, Any]:
    with path.open("rb") as stream:
        response = requests.post(
            f"{base.rstrip('/')}/upload/file",
            headers={"Authorization": f"Bearer {token}"},
            files={"file": (path.name, stream, "application/zip")},
            timeout=90,
        )
    response.raise_for_status()
    body = response.json()
    if int(body.get("code", -1)) != 0:
        raise RuntimeError(f"file upload failed: {body.get('message')}")
    return body.get("data") or {}


def resumed_activity(harness: P1Harness) -> str:
    activities = harness.adb_run(
        "shell", "dumpsys", "activity", "activities", check=True
    ).stdout
    return next(
        (line.strip() for line in activities.splitlines() if "mResumedActivity" in line),
        "",
    )


def adb_capture(harness: P1Harness, name: str) -> Path:
    remote = f"/sdcard/{name}.png"
    local = harness.run_dir / f"{name}.png"
    harness.adb_run("shell", "screencap", "-p", remote, check=True)
    harness.adb_run("pull", remote, str(local), check=True)
    return local


def select_document(harness: P1Harness, file_name: str) -> None:
    # Querying Huawei DocumentsUI through UIAutomator2 re-activates Flutter,
    # and the stock hierarchy dumper conflicts with the UIAutomator2 process.
    # Keep the whole picker phase on raw ADB with coordinates scaled from the
    # physical display. Search by the unique timestamp so shell input remains
    # ASCII-only and the result list contains exactly one row.
    size = harness.adb_run("shell", "wm", "size", check=True).stdout
    match = re.search(r"(?:Override|Physical) size: (\d+)x(\d+)", size)
    if match is None:
        raise RuntimeError(f"could not read Android display size: {size.strip()}")
    width, height = (int(match.group(1)), int(match.group(2)))
    token_match = re.search(r"IM204-CANCEL-(\d+)-", file_name)
    search_term = token_match.group(1) if token_match else file_name
    harness.adb_run(
        "shell",
        "input",
        "tap",
        str(int(width * 0.80)),
        str(int(height * 0.088)),
        check=True,
    )
    time.sleep(0.8)
    for digit in search_term:
        if not digit.isdigit():
            raise RuntimeError(f"picker search token is not numeric: {search_term}")
        harness.adb_run("shell", "input", "keyevent", f"KEYCODE_{digit}", check=True)
    harness.adb_run("shell", "input", "keyevent", "66")
    time.sleep(2)
    remote_capture = "/sdcard/p2b4-picker-filtered.png"
    local_capture = harness.run_dir / "im204-picker-filtered.png"
    harness.adb_run("shell", "screencap", "-p", remote_capture, check=True)
    harness.adb_run("pull", remote_capture, str(local_capture), check=True)

    # Huawei DocumentsUI can render a single filtered result as a large tile
    # whose center is around 30% of the physical display height. Larger files
    # sometimes use the lower list layout covered by the later ratios.
    for result_ratio in (0.30, 0.34, 0.39, 0.43, 0.48, 0.53):
        harness.adb_run(
            "shell",
            "input",
            "tap",
            # The single-result grid tile occupies the left half of Huawei's
            # picker; the physical screen center can land just outside it.
            str(int(width * 0.25)),
            str(int(height * result_ratio)),
            check=True,
        )
        time.sleep(1.2)
        if "com.android.documentsui/.picker.PickActivity" not in resumed_activity(
            harness
        ):
            return
    raise RuntimeError(f"document picker result did not open: {file_name}")


def open_file_picker(harness: P1Harness, file_name: str) -> None:
    harness.click_input_side("left")
    file_action = harness.device(description="文件")
    if not file_action.wait(timeout=5):
        file_action = harness.device(text="文件")
    if not file_action.exists(timeout=0.5):
        # The attachment sheet is paged. On the current online settings the
        # first eight actions fill page one and File is on page two.
        width, height = harness.device.window_size()
        harness.device.swipe(
            int(width * 0.86),
            int(height * 0.89),
            int(width * 0.14),
            int(height * 0.89),
            duration=0.45,
        )
        file_action = harness.device(description="文件")
        if not file_action.wait(timeout=4):
            file_action = harness.device(text="文件")
    if not file_action.wait(timeout=2):
        raise RuntimeError("attachment file action missing")
    file_bounds = file_action.info.get("bounds") or {}
    if not all(key in file_bounds for key in ("left", "top", "right", "bottom")):
        raise RuntimeError(f"attachment file bounds missing: {file_bounds}")
    before_activity = resumed_activity(harness)
    adb_capture(harness, "im204-before-file-tap")
    # Do not switch away from UIAutomator2's IME here: Huawei stops its package
    # and restores the app's previous profile route. The picker search below
    # uses raw digit key events, so no IME change is required.
    harness.adb_run(
        "shell",
        "input",
        "tap",
        str((int(file_bounds["left"]) + int(file_bounds["right"])) // 2),
        str((int(file_bounds["top"]) + int(file_bounds["bottom"])) // 2),
        check=True,
    )
    time.sleep(1.2)
    after_activity = resumed_activity(harness)
    adb_capture(harness, "im204-after-file-tap")
    if "com.android.documentsui/.picker.PickActivity" not in after_activity:
        raise RuntimeError(
            "system document picker did not open; "
            f"bounds={file_bounds}; before={before_activity}; after={after_activity}"
        )
    select_document(harness, file_name)


def write_outputs(run_dir: Path, payload: dict[str, Any]) -> None:
    (run_dir / "p2b4-validation-results.json").write_text(
        json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    lines = [
        "# P2-B4 文件与撤回双真机验证报告",
        "",
        "| 用例 | 状态 | 结论 |",
        "|---|---|---|",
    ]
    lines.extend(
        f"| {item['case_id']} | {item['status']} | {item['detail']} |"
        for item in payload["cases"]
    )
    (run_dir / "P2B4_REAL_DEVICE_VALIDATION_REPORT.md").write_text(
        "\n".join(lines), encoding="utf-8"
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", required=True)
    parser.add_argument("--run-dir", required=True)
    parser.add_argument("--adb", required=True)
    parser.add_argument("--sender", required=True)
    parser.add_argument("--receiver", required=True)
    parser.add_argument("--apk-sha256", required=True)
    parser.add_argument("--package", default="com.genericim.ma100")
    parser.add_argument("--base", default="https://api.example.com/api/v1")
    parser.add_argument("--username", default="smoke_alice")
    parser.add_argument("--password", default="Smoke123")
    parser.add_argument("--reuse-visible-expired", action="store_true")
    args = parser.parse_args()

    repo = Path(args.repo).resolve()
    run_dir = Path(args.run_dir).resolve()
    run_dir.mkdir(parents=True, exist_ok=True)
    sender = P1Harness(repo, run_dir / args.sender, args.adb, args.sender, args.package)
    receiver = P1Harness(
        repo, run_dir / args.receiver, args.adb, args.receiver, args.package
    )
    for harness in (sender, receiver):
        harness.adb_run("logcat", "-c")

    login = request_json(
        args.base,
        "/auth/login",
        data={
            "username": args.username,
            "password": args.password,
            "device_id": "p2b4-physical-validation",
            "device_type": "android",
            "device_name": "P2B4 Physical Validation",
        },
    )
    login_data = login.get("data") or {}
    if int(login.get("code", -1)) != 0 or not login_data.get("token"):
        raise RuntimeError(f"QA API login failed: {login.get('message')}")
    token = str(login_data["token"])
    chat_id = find_private_chat(args.base, token, "smoke_bob")
    stamp = datetime.now().strftime("%H%M%S")
    cases: list[dict[str, Any]] = []

    # Start the real two-minute boundary before the other two cases.
    expired_token = f"IM202_EXPIRED_{stamp}"
    expired_ack: dict[str, Any] = {}
    if args.reuse_visible_expired:
        expired_started = time.time() - 123
    else:
        expired_ack = api_send(
            args.base,
            token,
            {
                "chat_id": chat_id,
                "type": 1,
                "content": {"text": expired_token},
                "msg_id": str(uuid.uuid4()),
            },
        )
        expired_started = time.time()

    try:
        fixture = repo / "artifacts/real-device-qa/im400-two-device-resume-20260715/file-fixtures/IM188-normal.zip"
        if not fixture.exists():
            fixture = repo / "artifacts/real-device-qa/im400-two-device-resume-20260715/revoke-batch/IM204-sending-valid-50MB.zip"
        open_name = f"IM191-OPEN-{stamp}.zip"
        open_copy = run_dir / open_name
        shutil.copyfile(fixture, open_copy)
        upload = api_upload(args.base, token, open_copy)
        remote_url = upload.get("url")
        if not remote_url:
            raise RuntimeError("upload response did not contain a URL")
        api_send(
            args.base,
            token,
            {
                "chat_id": chat_id,
                "type": 5,
                "content": {
                    "file": {
                        "url": remote_url,
                        "name": open_name,
                        "size": open_copy.stat().st_size,
                        "mime_type": "application/zip",
                    }
                },
                "msg_id": str(uuid.uuid4()),
            },
        )
        evidence = receiver.open_private("smoke_alice", "im191-receiver")
        assert wait_until(lambda: node_containing(receiver, open_name) is not None, 15), (
            "new file bubble did not reach the receiver"
        )
        file_node = node_containing(receiver, open_name)
        assert file_node is not None
        tap_node(receiver, file_node)
        time.sleep(4)
        file_node = node_containing(receiver, open_name)
        assert file_node is not None
        evidence += receiver.snapshot("im191-downloaded")
        tap_node(receiver, file_node)
        assert wait_until(
            lambda: receiver.device.app_current().get("package") != args.package,
            8,
        ), "Android system chooser or external file app was not opened"
        current = receiver.device.app_current()
        evidence += receiver.snapshot("im191-system-open")
        activity_dump = receiver.adb_run("shell", "dumpsys", "activity", "activities").stdout
        activity_path = run_dir / "im191-system-activity.txt"
        activity_path.write_text(activity_dump, encoding="utf-8", errors="replace")
        evidence.append(rel(activity_path, repo))
        cases.append(
            {
                "case_id": "IM-191",
                "status": "PASS",
                "detail": f"downloaded ZIP opened through Android content URI; foreground={current.get('package')}/{current.get('activity')}",
                "evidence": evidence,
            }
        )
        receiver.device.press("back")
    except Exception as exc:
        cases.append(
            {
                "case_id": "IM-191",
                "status": "FAIL",
                "detail": str(exc),
                "evidence": receiver.snapshot("im191-failed"),
            }
        )

    try:
        cancel_name = f"IM204-CANCEL-{stamp}-50MB.zip"
        cancel_source = (
            repo
            / "artifacts/real-device-qa/im400-two-device-resume-20260715/revoke-batch/IM204-sending-valid-50MB.zip"
        )
        assert cancel_source.exists(), "50MB cancellation fixture is missing"
        sender.adb_run(
            "push",
            str(cancel_source),
            f"/sdcard/Download/{cancel_name}",
            check=True,
        )
        evidence = sender.open_private("smoke_bob", "im204-sender")
        open_file_picker(sender, cancel_name)
        assert wait_until(lambda: node_containing(sender, cancel_name) is not None, 8), (
            "optimistic sending bubble did not appear"
        )
        pending = node_containing(sender, cancel_name)
        assert pending is not None
        evidence += sender.snapshot("im204-uploading")
        long_press_node(sender, pending)
        assert sender.device(description="撤回").wait(timeout=5), (
            "sending message recall action is missing"
        )
        evidence += sender.snapshot("im204-cancel-action")
        sender.device(description="撤回").click()
        assert wait_until(lambda: node_containing(sender, cancel_name) is None, 8), (
            "cancelled upload left a local ghost message"
        )
        evidence += sender.snapshot("im204-sender-clean")
        receiver.device.press("back")
        receiver.open_private("smoke_alice", "im204-receiver")
        time.sleep(4)
        evidence += receiver.snapshot("im204-receiver-clean")
        server_messages = list_messages(args.base, token, chat_id, 100)
        server_has_file = any(
            cancel_name
            in json.dumps(item.get("content") or {}, ensure_ascii=False)
            for item in server_messages
        )
        assert not server_has_file, "cancelled file reached the authoritative message list"
        assert node_containing(receiver, cancel_name) is None, (
            "cancelled file appeared on the receiver"
        )
        cases.append(
            {
                "case_id": "IM-204",
                "status": "PASS",
                "detail": "50MB upload was cancelled from the sending bubble; no local ghost and no receiver/server message remained",
                "evidence": evidence,
            }
        )
    except Exception as exc:
        cases.append(
            {
                "case_id": "IM-204",
                "status": "FAIL",
                "detail": str(exc),
                "evidence": sender.snapshot("im204-failed")
                + receiver.snapshot("im204-failed-receiver"),
            }
        )

    try:
        remaining = 123 - (time.time() - expired_started)
        if remaining > 0:
            time.sleep(remaining)
        evidence = sender.open_private("smoke_bob", "im202-sender")
        wait_until(lambda: node_containing(sender, expired_token) is not None, 4)
        expired_node = node_containing(sender, expired_token)
        fixture_description = expired_token
        if expired_node is None and args.reuse_visible_expired:
            width, _ = sender.device.window_size()
            candidates = [
                item
                for item in sender.nodes()
                if item["clickable"]
                and item["left"] > int(width * 0.30)
                and item["right"] > int(width * 0.85)
                and item["bottom"] - item["top"] > 100
                and re.search(r"\d{1,2}:\d{2}", item["desc"])
                and "当前为" not in item["desc"]
            ]
            if candidates:
                expired_node = max(candidates, key=lambda item: item["bottom"])
                fixture_description = expired_node["desc"].replace("\n", " / ")
        assert expired_node is not None
        long_press_node(sender, expired_node)
        expired_label = "撤回（已超过2分钟）"
        assert sender.hierarchy_contains(expired_label), (
            "expired outgoing message did not expose an explicit recall state"
        )
        evidence += sender.snapshot("im202-expired-menu")
        sender.device(description=expired_label).click()
        assert wait_until(lambda: sender.hierarchy_contains("已超过撤回时限"), 4), (
            "expired recall action did not explain the failure reason"
        )
        evidence += sender.snapshot("im202-expired-reason")
        server_messages = list_messages(args.base, token, chat_id, 100)
        if expired_ack:
            still_exists = any(
                str(item.get("msg_id")) == str(expired_ack.get("msg_id"))
                or expired_token
                in json.dumps(item.get("content") or {}, ensure_ascii=False)
                for item in server_messages
            )
            assert still_exists, "expired message was unexpectedly removed"
        cases.append(
            {
                "case_id": "IM-202",
                "status": "PASS",
                "detail": f"an outgoing fixture older than two minutes ({fixture_description}) retained Recall with an explicit expiry label and reason",
                "evidence": evidence,
            }
        )
    except Exception as exc:
        cases.append(
            {
                "case_id": "IM-202",
                "status": "FAIL",
                "detail": str(exc),
                "evidence": sender.snapshot("im202-failed"),
            }
        )

    fatal_lines: list[str] = []
    for harness, name in ((sender, "sender"), (receiver, "receiver")):
        log_path = run_dir / f"{name}-logcat.txt"
        log_path.write_text(
            harness.adb_run("logcat", "-d", "-v", "threadtime").stdout,
            encoding="utf-8",
            errors="replace",
        )
        fatal_lines.extend(
            line
            for line in log_path.read_text(encoding="utf-8", errors="replace").splitlines()
            if "ANR in com.genericim.ma100" in line
            or "Process: com.genericim.ma100" in line
        )
    payload = {
        "environment": {
            "finished_at": datetime.now().astimezone().isoformat(timespec="seconds"),
            "devices": [args.sender, args.receiver],
            "apk_sha256": args.apk_sha256,
            "fatal_anr_count": len(fatal_lines),
        },
        "cases": cases,
    }
    write_outputs(run_dir, payload)
    for item in cases:
        print(
            f"[P2-B4] {item['case_id']}: {item['status']} - {item['detail']}",
            flush=True,
        )
    return 1 if fatal_lines or any(item["status"] != "PASS" for item in cases) else 0


if __name__ == "__main__":
    raise SystemExit(main())
