#!/usr/bin/env python3
"""P0 chat image rollback validation on two physical Android devices."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import Any
from urllib.parse import urlparse
from urllib.request import urlopen


SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from run_p1_fix_validation import P1Harness, find_private_chat, list_messages, request_json
from run_p2b2_image_validation import select_document, tap_latest_media_bubble, wait_for_new_image


def login(base: str, username: str, password: str, device_id: str) -> dict[str, Any]:
    response = request_json(
        base,
        "/auth/login",
        data={
            "username": username,
            "password": password,
            "device_id": device_id,
            "device_type": "android",
            "device_name": "P0 physical acceptance",
        },
    )
    if int(response.get("code", -1)) != 0:
        raise RuntimeError(f"login failed for {username}: {response.get('message')}")
    return response.get("data") or {}


def push_fixture(
    adb: str,
    serial: str,
    source: Path,
    name: str,
    album_name: str,
) -> None:
    # Put the controlled fixture slightly ahead of existing rows so the
    # system photo picker's default Recent grid exposes it first.
    captured_at_ms = int(time.time() * 1000) + 300_000
    captured_at_seconds = captured_at_ms // 1000
    remote = f"/sdcard/Download/{name}"
    subprocess.run([adb, "-s", serial, "push", str(source), remote], check=True)
    subprocess.run([adb, "-s", serial, "shell", "touch", remote], check=True)
    subprocess.run(
        [
            adb,
            "-s",
            serial,
            "shell",
            "am",
            "broadcast",
            "-a",
            "android.intent.action.MEDIA_SCANNER_SCAN_FILE",
            "-d",
            f"file://{remote}",
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    # Android's modern photo picker reads MediaStore rather than raw files in
    # Download. Insert a fresh controlled row and stream the fixture into it so
    # it appears as the newest first thumbnail on Huawei and Samsung.
    subprocess.run(
        [
            adb,
            "-s",
            serial,
            "shell",
            "content",
            "insert",
            "--uri",
            "content://media/external/images/media",
            "--bind",
            f"_display_name:s:{name}",
            "--bind",
            "mime_type:s:image/png",
            "--bind",
            f"relative_path:s:Pictures/{album_name}",
            "--bind",
            f"datetaken:l:{captured_at_ms}",
            "--bind",
            f"date_added:l:{captured_at_seconds}",
        ],
        check=True,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    listing = subprocess.run(
        [
            adb,
            "-s",
            serial,
            "shell",
            "content",
            "query",
            "--uri",
            "content://media/external/images/media",
            "--projection",
            "_id:_display_name:bucket_display_name",
        ],
        check=True,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    ).stdout
    ids = []
    for line in listing.splitlines():
        if not re.search(rf"(?:^|, )_display_name={re.escape(name)}(?:,|$)", line):
            continue
        match = re.search(r"_id=(\d+)", line)
        if match:
            ids.append(int(match.group(1)))
    if not ids:
        raise RuntimeError(f"MediaStore row missing after insert: {name}")
    media_id = max(ids)
    subprocess.run(
        [
            adb,
            "-s",
            serial,
            "shell",
            (
                f"cat {remote} | content write "
                f"--uri content://media/external/images/media/{media_id}"
            ),
        ],
        check=True,
    )
    listing = subprocess.run(
        [
            adb,
            "-s",
            serial,
            "shell",
            "content",
            "query",
            "--uri",
            f"content://media/external/images/media/{media_id}",
            "--projection",
            "_id:_display_name:bucket_display_name:_size",
        ],
        check=True,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    ).stdout
    expected_size = source.stat().st_size
    actual_size_match = re.search(r"_size=(\d+)", listing)
    actual_size = int(actual_size_match.group(1)) if actual_size_match else -1
    if actual_size != expected_size or f"bucket_display_name={album_name}" not in listing:
        raise RuntimeError(
            f"MediaStore fixture verification failed: expected_size={expected_size}, "
            f"row={listing.strip()}"
        )


def image_url(message: dict[str, Any]) -> str:
    content = message.get("content") or {}
    if isinstance(content, str):
        try:
            content = json.loads(content)
        except json.JSONDecodeError:
            content = {}
    media = content.get("media") or {}
    return str(media.get("url") or "")


def image_media_id(message: dict[str, Any]) -> str:
    content = message.get("content") or {}
    if isinstance(content, str):
        try:
            content = json.loads(content)
        except json.JSONDecodeError:
            content = {}
    media = content.get("media") or {}
    return str(media.get("media_id") or "").strip()


def verify_private_media_hash(
    base: str,
    token: str,
    message: dict[str, Any],
    expected_sha256: str,
) -> str:
    media_id = image_media_id(message)
    if not media_id:
        raise AssertionError("server image message is missing media_id")
    response = request_json(base, f"/media/{media_id}/access-url", token)
    access_url = str((response.get("data") or {}).get("url") or "")
    if not access_url:
        raise AssertionError("private media access URL is missing")
    actual_sha256 = hashlib.sha256(
        urlopen(access_url, timeout=30).read()
    ).hexdigest()
    if actual_sha256 != expected_sha256:
        raise AssertionError(
            "the system picker did not upload the controlled fixture: "
            f"expected_sha256={expected_sha256}, "
            f"actual_sha256={actual_sha256}"
        )
    return actual_sha256


def open_album_and_send(harness: P1Harness, file_name: str, album_name: str) -> None:
    # Recover from a stale modal (for example the red-packet page left by a
    # previous failed UI attempt) before opening the chat attachment menu.
    for _ in range(3):
        if harness.device(className="android.widget.EditText").exists(timeout=1):
            break
        harness.device.press("back")
        time.sleep(0.8)
    harness.click_input_side("left")
    album = harness.device(description="相册")
    if not album.click_exists(timeout=5):
        if not harness.device(text="相册").click_exists(timeout=3):
            raise RuntimeError("attachment album action missing")
    try:
        select_document(harness, file_name)
        return
    except RuntimeError as exc:
        if "search action missing" not in str(exc):
            raise
    # Huawei/Samsung can use the in-app photo picker, which intentionally has
    # no filename search. Enter this run's unique, one-image MediaStore album;
    # never fall back to a personal album or an unverified Recent tile.
    if not harness.device(description="Recent").click_exists(timeout=2):
        raise RuntimeError("photo picker album selector missing")
    album_node = None
    for _ in range(8):
        album_node = next(
            (
                node
                for node in harness.nodes()
                if album_name in str(node.get("desc") or "")
                and node.get("clickable")
            ),
            None,
        )
        if album_node is not None:
            break
        width, height = harness.device.window_size()
        harness.device.swipe(
            int(width * 0.5),
            int(height * 0.82),
            int(width * 0.5),
            int(height * 0.30),
            duration=0.45,
        )
        time.sleep(0.7)
    if album_node is not None:
        harness.device.click(
            (album_node["left"] + album_node["right"]) // 2,
            (album_node["top"] + album_node["bottom"]) // 2,
        )
    else:
        # Vendor pickers can cache the album list even after the app restarts.
        # Never fall back to an older P0QA album because that can upload stale
        # bytes while the UI still appears successful. Return to Recent; the
        # fixture was inserted with a future datetaken and is the first tile.
        harness.device.press("back")
    time.sleep(1)
    width, height = harness.device.window_size()
    harness.device.click(int(width * 0.13), int(height * 0.17))
    time.sleep(1)
    # Preserve the selected fixture bytes so the S3 object can be verified
    # byte-for-byte. This toggle belongs to the in-app photo picker.
    if not harness.device(description="原图").click_exists(timeout=2):
        harness.device(text="原图").click_exists(timeout=1)
    time.sleep(0.5)
    if not harness.device(descriptionStartsWith="发送").click_exists(timeout=2):
        if not harness.device(textStartsWith="发送").click_exists(timeout=2):
            raise RuntimeError("photo picker send action missing after selecting the newest image")


def wait_receiver_message(
    base: str,
    token: str,
    chat_id: str,
    message_id: str,
    timeout: int = 60,
) -> dict[str, Any]:
    deadline = time.time() + timeout
    while time.time() < deadline:
        for item in list_messages(base, token, chat_id, 100):
            if str(item.get("msg_id") or "") == message_id:
                return item
        time.sleep(2)
    raise AssertionError(f"receiver did not observe message {message_id}")


def message_display_time(message: dict[str, Any]) -> str:
    raw = str(message.get("created_at") or "").strip()
    if not raw:
        raise AssertionError("server image message is missing created_at")
    try:
        return datetime.fromisoformat(raw.replace("Z", "+00:00")).astimezone().strftime("%H:%M")
    except ValueError as exc:
        raise AssertionError(f"invalid server message created_at: {raw}") from exc


def image_time_count(hierarchy: str, display_time: str) -> int:
    pattern = (
        r'class="android\.widget\.ImageView"[^>]*'
        rf'content-desc="{re.escape(display_time)}"'
    )
    return len(re.findall(pattern, hierarchy))


def visible_image_time_count(harness: P1Harness, display_time: str) -> int:
    return image_time_count(
        harness.device.dump_hierarchy(compressed=False),
        display_time,
    )


def wait_for_live_image_bubble(
    harness: P1Harness,
    display_time: str,
    baseline_count: int,
    timeout: int = 15,
) -> None:
    deadline = time.time() + timeout
    while time.time() < deadline:
        if visible_image_time_count(harness, display_time) > baseline_count:
            return
        time.sleep(1)
    raise AssertionError(
        "receiver received the live message but its image did not finish "
        f"loading for server time {display_time}"
    )


def error_log(harness: P1Harness) -> tuple[str, list[str]]:
    output = harness.adb_run("logcat", "-d", "-v", "threadtime").stdout
    fatal_markers = (
        "FATAL EXCEPTION",
        "ANR in com.genericim.ma100",
        "Unhandled Exception",
    )
    # The native bootstrap forwards Flutter diagnostics to logcat. Material
    # emits a known debug-only ListTile visibility diagnostic on Android; it
    # is not a crash, ANR, or unhandled exception and must not fail media QA.
    benign_flutter_diagnostics = (
        "ListTile background color or ink splashes may be invisible.",
    )
    hits = [
        line
        for line in output.splitlines()
        if any(marker in line for marker in fatal_markers)
        or (
            "FlutterError" in line
            and not any(item in line for item in benign_flutter_diagnostics)
        )
    ]
    return output, hits


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", required=True)
    parser.add_argument("--run-dir", required=True)
    parser.add_argument("--adb", required=True)
    parser.add_argument("--device-a", required=True)
    parser.add_argument("--device-b", required=True)
    parser.add_argument("--fixture", required=True)
    parser.add_argument("--apk-sha256", required=True)
    parser.add_argument("--base", default="http://192.168.1.100:8080/api/v1")
    parser.add_argument("--alice", default="smoke_alice")
    parser.add_argument("--bob", default="smoke_bob")
    parser.add_argument("--password", default="Smoke123")
    parser.add_argument("--package", default="com.genericim.ma100")
    parser.add_argument("--expect-direct-upload", action="store_true")
    args = parser.parse_args()

    repo = Path(args.repo).resolve()
    run_dir = Path(args.run_dir).resolve()
    run_dir.mkdir(parents=True, exist_ok=True)
    fixture = Path(args.fixture).resolve()
    fixture_hash = hashlib.sha256(fixture.read_bytes()).hexdigest()

    alice_login = login(args.base, args.alice, args.password, "p0-physical-api-alice")
    bob_login = login(args.base, args.bob, args.password, "p0-physical-api-bob")
    alice_token = str(alice_login["token"])
    bob_token = str(bob_login["token"])
    alice_chat = find_private_chat(args.base, alice_token, args.bob)
    bob_chat = find_private_chat(args.base, bob_token, args.alice)
    if alice_chat != bob_chat:
        raise AssertionError("Alice/Bob private chat IDs do not match")

    run_stamp = datetime.now().strftime("%H%M%S")
    album_name = f"P0QA{run_stamp}"
    file_a = f"P0_HUAWEI_TO_SAMSUNG_{run_stamp}.png"
    file_b = f"P0_SAMSUNG_TO_HUAWEI_{run_stamp}.png"
    push_fixture(args.adb, args.device_a, fixture, file_a, album_name)
    push_fixture(args.adb, args.device_b, fixture, file_b, album_name)
    # PhotoManager keeps an in-process asset cache. Restart after seeding the
    # controlled MediaStore rows so both pickers refresh before the first send.
    for serial in (args.device_a, args.device_b):
        subprocess.run(
            [args.adb, "-s", serial, "shell", "am", "force-stop", args.package],
            check=True,
        )
        subprocess.run(
            [
                args.adb,
                "-s",
                serial,
                "shell",
                "am",
                "start",
                "-W",
                "-n",
                f"{args.package}/.MainActivity",
            ],
            check=True,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
        )
    time.sleep(8)

    device_a = P1Harness(repo, run_dir / "device-a-huawei", args.adb, args.device_a, args.package)
    device_b = P1Harness(repo, run_dir / "device-b-samsung", args.adb, args.device_b, args.package)
    device_a.adb_run("logcat", "-c")
    device_b.adb_run("logcat", "-c")
    cases: list[dict[str, Any]] = []
    message_ids: list[str] = []

    settings = request_json(args.base, "/app/settings").get("data") or {}
    direct = settings.get("chat_image_direct_upload") or {}
    expected_enabled = args.expect_direct_upload
    expected_rollout = 100 if expected_enabled else 0
    platforms = [str(item).lower() for item in (direct.get("platforms") or [])]
    config_ok = (
        direct.get("enabled") is expected_enabled
        and int(direct.get("rollout_percent") or 0) == expected_rollout
        and (not expected_enabled or "android" in platforms)
    )
    cases.append(
        {
            "case_id": "P0-RD-001",
            "status": "PASS" if config_ok else "FAIL",
            "detail": (
                f"Chat image direct upload matches the expected "
                f"{'enabled' if expected_enabled else 'disabled'} state: {direct}"
            ),
            "evidence": [],
        }
    )

    def send_case(
        case_id: str,
        sender: P1Harness,
        receiver: P1Harness,
        sender_token: str,
        receiver_token: str,
        receiver_username: str,
        sender_username: str,
        file_name: str,
        label: str,
    ) -> None:
        evidence: list[str] = []
        try:
            # Strict live-delivery precondition: the receiver enters the chat
            # before the sender starts and must remain on this exact page.
            evidence += receiver.open_private(
                sender_username,
                f"{label}-receiver-live-waiting",
            )
            time.sleep(2)
            evidence += receiver.snapshot(f"{label}-receiver-live-before")
            receiver_baseline_hierarchy = receiver.device.dump_hierarchy(
                compressed=False,
            )
            evidence += sender.open_private(receiver_username, f"{label}-sender-chat")
            evidence += sender.snapshot(f"{label}-before-send")
            previous = {
                str(item.get("msg_id") or "")
                for item in list_messages(args.base, sender_token, alice_chat, 100)
            }
            started_at = time.time()
            open_album_and_send(sender, file_name, album_name)
            message = wait_for_new_image(args.base, sender_token, alice_chat, previous)
            upload_seconds = round(time.time() - started_at, 3)
            msg_id = str(message.get("msg_id") or "")
            url = image_url(message)
            if not msg_id or not url:
                raise AssertionError("server image message is missing msg_id or URL")
            wait_receiver_message(args.base, receiver_token, bob_chat, msg_id)
            uploaded_sha256 = verify_private_media_hash(
                args.base,
                receiver_token,
                message,
                fixture_hash,
            )
            display_time = message_display_time(message)
            before_live_count = image_time_count(
                receiver_baseline_hierarchy,
                display_time,
            )
            wait_for_live_image_bubble(
                receiver,
                display_time,
                before_live_count,
            )
            evidence += sender.snapshot(f"{label}-sender-sent")
            evidence += receiver.snapshot(f"{label}-receiver-live-received")
            tap_latest_media_bubble(receiver)
            time.sleep(3)
            evidence += receiver.snapshot(f"{label}-receiver-live-preview")
            receiver.device.press("back")
            message_ids.append(msg_id)
            cases.append(
                {
                    "case_id": case_id,
                    "status": "PASS",
                    "detail": (
                        f"Receiver stayed on the open chat page, displayed the "
                        f"new image bubble live, and opened it in preview; "
                        f"server confirmation took {upload_seconds}s."
                    ),
                    "evidence": evidence,
                    "data": {
                        "msg_id": msg_id,
                        "url_host": urlparse(url).hostname,
                        "server_confirmation_seconds": upload_seconds,
                        "uploaded_sha256": uploaded_sha256,
                    },
                }
            )
        except Exception as exc:
            evidence += sender.snapshot(f"{label}-sender-failed")
            evidence += receiver.snapshot(f"{label}-receiver-failed")
            cases.append(
                {
                    "case_id": case_id,
                    "status": "FAIL",
                    "detail": str(exc),
                    "evidence": evidence,
                }
            )

    send_case(
        "P0-RD-002",
        device_a,
        device_b,
        alice_token,
        bob_token,
        args.bob,
        args.alice,
        file_a,
        "huawei-to-samsung",
    )
    send_case(
        "P0-RD-003",
        device_b,
        device_a,
        bob_token,
        alice_token,
        args.alice,
        args.bob,
        file_b,
        "samsung-to-huawei",
    )

    restart_evidence: list[str] = []
    try:
        for harness, peer, label in (
            (device_a, args.bob, "huawei"),
            (device_b, args.alice, "samsung"),
        ):
            harness.device.app_stop(args.package)
            harness.device.app_start(args.package, wait=True)
            time.sleep(7)
            restart_evidence += harness.open_private(peer, f"restart-{label}")
            time.sleep(2)
            restart_evidence += harness.snapshot(f"restart-{label}-history")
        cases.append(
            {
                "case_id": "P0-RD-004",
                "status": "PASS",
                "detail": "Both apps restarted without re-login and the private image conversation reopened.",
                "evidence": restart_evidence,
            }
        )
    except Exception as exc:
        cases.append(
            {
                "case_id": "P0-RD-004",
                "status": "FAIL",
                "detail": str(exc),
                "evidence": restart_evidence,
            }
        )

    all_hits: list[str] = []
    for harness, label in ((device_a, "huawei"), (device_b, "samsung")):
        log, hits = error_log(harness)
        log_path = run_dir / f"{label}-logcat.log"
        log_path.write_text(log, encoding="utf-8")
        all_hits.extend(f"{label}: {item}" for item in hits)
    cases.append(
        {
            "case_id": "P0-RD-005",
            "status": "PASS" if not all_hits else "FAIL",
            "detail": "No Fatal/ANR/FlutterError markers." if not all_hits else "; ".join(all_hits[:10]),
            "evidence": [
                str((run_dir / "huawei-logcat.log").relative_to(repo)).replace("\\", "/"),
                str((run_dir / "samsung-logcat.log").relative_to(repo)).replace("\\", "/"),
            ],
        }
    )

    payload = {
        "environment": {
            "finished_at": datetime.now().astimezone().isoformat(timespec="seconds"),
            "devices": [args.device_a, args.device_b],
            "accounts": [args.alice, args.bob],
            "apk_sha256": args.apk_sha256,
            "fixture_sha256": fixture_hash,
            "base": args.base,
        },
        "chat_id": alice_chat,
        "message_ids": message_ids,
        "cases": cases,
    }
    result_path = run_dir / "p0-real-device-results.json"
    result_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    passed = sum(1 for item in cases if item["status"] == "PASS")
    failed = sum(1 for item in cases if item["status"] == "FAIL")
    report = [
        "# P0 聊天图片双真机验收报告",
        "",
        f"- 时间：{payload['environment']['finished_at']}",
        f"- 设备：{args.device_a} / {args.device_b}",
        f"- APK SHA256：`{args.apk_sha256}`",
        f"- 受控测试图 SHA256：`{fixture_hash}`",
        f"- 结果：PASS {passed} / FAIL {failed}",
        "",
        "| 用例 | 结果 | 结论 |",
        "| --- | --- | --- |",
    ]
    report.extend(
        f"| {item['case_id']} | {item['status']} | {str(item['detail']).replace('|', '/')} |"
        for item in cases
    )
    (run_dir / "P0_REAL_DEVICE_ACCEPTANCE_REPORT.md").write_text(
        "\n".join(report) + "\n", encoding="utf-8"
    )
    for item in cases:
        print(f"[P0-RD] {item['case_id']}: {item['status']} - {item['detail']}", flush=True)
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
