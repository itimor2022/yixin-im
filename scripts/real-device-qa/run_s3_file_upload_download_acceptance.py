#!/usr/bin/env python3
"""Upload and download one ordinary file through two physical Android devices."""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import Any
from urllib.parse import urljoin

import requests


SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from run_p1_fix_validation import (  # noqa: E402
    P1Harness,
    find_private_chat,
    list_messages,
    request_json,
)
from run_p2b4_file_revoke_validation import (  # noqa: E402
    node_containing,
    open_file_picker,
    tap_node,
    wait_until,
)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest().upper()


def message_content(message: dict[str, Any]) -> dict[str, Any]:
    content = message.get("content") or {}
    if isinstance(content, str):
        content = json.loads(content)
    if not isinstance(content, dict):
        raise RuntimeError(f"unexpected message content: {content!r}")
    return content


def wait_for_file_message(
    base: str,
    token: str,
    chat_id: str,
    file_name: str,
    existing_ids: set[str],
    timeout: int = 120,
) -> dict[str, Any]:
    deadline = time.time() + timeout
    while time.time() < deadline:
        for message in list_messages(base, token, chat_id, 100):
            if str(message.get("msg_id") or "") in existing_ids:
                continue
            if file_name in json.dumps(
                message_content(message), ensure_ascii=False
            ):
                return message
        time.sleep(2)
    raise AssertionError(f"file message did not reach the server: {file_name}")


def download_message_file(
    base: str,
    token: str,
    message: dict[str, Any],
    target: Path,
) -> tuple[str, str]:
    content = message_content(message)
    file_data = content.get("file") or {}
    raw_url = str(file_data.get("url") or "")
    if not raw_url:
        raise AssertionError(f"file URL missing from message: {content}")
    url = raw_url if raw_url.startswith(("http://", "https://")) else urljoin(
        f"{base.rstrip('/')}/", raw_url.lstrip("/")
    )
    response = requests.get(
        url,
        headers={"Authorization": f"Bearer {token}"},
        timeout=90,
    )
    response.raise_for_status()
    target.write_bytes(response.content)
    media_id = str(file_data.get("media_id") or content.get("media_id") or "")
    return url, media_id


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", required=True)
    parser.add_argument("--run-dir", required=True)
    parser.add_argument("--adb", required=True)
    parser.add_argument("--sender", required=True)
    parser.add_argument("--receiver", required=True)
    parser.add_argument("--apk-sha256", required=True)
    parser.add_argument("--base", default="http://192.168.1.100:8080/api/v1")
    parser.add_argument("--package", default="com.genericim.ma100")
    parser.add_argument("--alice", default="smoke_alice")
    parser.add_argument("--bob", default="smoke_bob")
    parser.add_argument("--password", default="Smoke123")
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
            "username": args.alice,
            "password": args.password,
            "device_id": "s3-file-physical-acceptance",
            "device_type": "android",
            "device_name": "S3 File Physical Acceptance",
        },
    )
    login_data = login.get("data") or {}
    if int(login.get("code", -1)) != 0 or not login_data.get("token"):
        raise RuntimeError(f"QA API login failed: {login.get('message')}")
    token = str(login_data["token"])
    chat_id = find_private_chat(args.base, token, args.bob)
    existing_ids = {
        str(message.get("msg_id") or "")
        for message in list_messages(args.base, token, chat_id, 100)
    }

    fixture = (
        repo
        / "artifacts/real-device-qa/im400-two-device-resume-20260715/file-fixtures/IM188-normal.zip"
    )
    if not fixture.exists():
        fixture = (
            repo
            / "artifacts/real-device-qa/im400-two-device-resume-20260715/revoke-batch/IM204-sending-valid-50MB.zip"
        )
    if not fixture.exists():
        raise FileNotFoundError("ordinary-file fixture is missing")
    stamp = datetime.now().strftime("%H%M%S")
    file_name = f"IM204-CANCEL-{stamp}-S3QA.zip"
    source = run_dir / file_name
    shutil.copyfile(fixture, source)
    expected_sha256 = sha256_file(source)
    sender.adb_run("push", str(source), f"/sdcard/Download/{file_name}", check=True)

    evidence: list[str] = []
    evidence += sender.open_private(args.bob, "s3-file-sender")
    open_file_picker(sender, file_name)
    message = wait_for_file_message(
        args.base, token, chat_id, file_name, existing_ids
    )
    assert wait_until(lambda: node_containing(sender, file_name) is not None, 20), (
        "successful file bubble did not appear on sender"
    )
    evidence += sender.snapshot("s3-file-uploaded")

    downloaded = run_dir / f"server-downloaded-{file_name}"
    download_url, media_id = download_message_file(
        args.base, token, message, downloaded
    )
    actual_sha256 = sha256_file(downloaded)
    assert actual_sha256 == expected_sha256, (
        f"downloaded bytes differ: expected={expected_sha256} actual={actual_sha256}"
    )

    evidence += receiver.open_private(args.alice, "s3-file-receiver")
    assert wait_until(lambda: node_containing(receiver, file_name) is not None, 30), (
        "file bubble did not reach receiver"
    )
    file_node = node_containing(receiver, file_name)
    assert file_node is not None
    evidence += receiver.snapshot("s3-file-before-download")
    tap_node(receiver, file_node)
    time.sleep(5)
    current = receiver.device.app_current()
    if current.get("package") == args.package:
        file_node = node_containing(receiver, file_name)
        assert file_node is not None, "downloaded file bubble disappeared"
        evidence += receiver.snapshot("s3-file-downloaded")
        tap_node(receiver, file_node)
        assert wait_until(
            lambda: receiver.device.app_current().get("package") != args.package,
            10,
        ), "Android system chooser or external file app was not opened"
        current = receiver.device.app_current()
    evidence += receiver.snapshot("s3-file-system-open")

    fatal_lines: list[str] = []
    for harness, label in ((sender, "sender"), (receiver, "receiver")):
        log = harness.adb_run("logcat", "-d", "-v", "threadtime").stdout
        log_path = run_dir / f"{label}-logcat.txt"
        log_path.write_text(log, encoding="utf-8", errors="replace")
        fatal_lines.extend(
            line
            for line in log.splitlines()
            if "ANR in com.genericim.ma100" in line
            or "Process: com.genericim.ma100" in line
            or "FATAL EXCEPTION" in line
        )
    assert not fatal_lines, f"fatal/ANR lines found: {len(fatal_lines)}"

    result = {
        "status": "PASS",
        "finished_at": datetime.now().astimezone().isoformat(timespec="seconds"),
        "devices": [args.sender, args.receiver],
        "apk_sha256": args.apk_sha256,
        "file_name": file_name,
        "size": source.stat().st_size,
        "expected_sha256": expected_sha256,
        "downloaded_sha256": actual_sha256,
        "message_id": message.get("msg_id"),
        "media_id": media_id,
        "download_url_host": requests.utils.urlparse(download_url).netloc,
        "external_open_package": current.get("package"),
        "external_open_activity": current.get("activity"),
        "fatal_anr_count": 0,
        "evidence": evidence,
    }
    result_path = run_dir / "s3-file-acceptance-result.json"
    result_path.write_text(
        json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print(json.dumps(result, ensure_ascii=False, indent=2), flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
