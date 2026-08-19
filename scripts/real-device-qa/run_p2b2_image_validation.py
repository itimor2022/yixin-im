#!/usr/bin/env python3
"""Physical-device validation for original-image and animated-GIF fixes."""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import sys
import time
from datetime import datetime
from pathlib import Path
from urllib.request import urlopen


SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from run_im400_full import rel  # noqa: E402
from run_p1_fix_validation import P1Harness, find_private_chat, list_messages  # noqa: E402


def wait_for_new_image(base: str, token: str, chat_id: str, previous: set[str]) -> dict:
    deadline = time.time() + 90
    while time.time() < deadline:
        messages = list_messages(base, token, chat_id, 100)
        match = next(
            (
                item
                for item in messages
                if str(item.get("msg_id")) not in previous and int(item.get("type") or 0) == 2
            ),
            None,
        )
        if match is not None:
            return match
        time.sleep(2)
    raise AssertionError("image message did not reach the authoritative server list")


def select_document(harness: P1Harness, file_name: str) -> None:
    search = harness.device(description="搜索")
    if not search.click_exists(timeout=8):
        raise RuntimeError("document picker search action missing")
    edit = harness.device(resourceId="com.android.documentsui:id/search_src_text")
    if not edit.exists(timeout=2):
        edit = harness.device(className="android.widget.AutoCompleteTextView")
    if not edit.wait(timeout=5):
        raise RuntimeError("document picker search input missing")
    edit.click()
    harness.device.send_keys(file_name, clear=True)
    harness.adb_run("shell", "input", "keyevent", "66")
    escaped = file_name.replace('"', '\\"')
    row = harness.device.xpath(
        '//*[@resource-id="com.android.documentsui:id/item_root" '
        f'and .//*[@resource-id="android:id/title" and @text="{escaped}"]]'
    )
    if not row.wait(timeout=10):
        raise RuntimeError(f"document picker result missing: {file_name}")
    row.click()


def open_attachment(harness: P1Harness) -> None:
    harness.click_input_side("left")
    if not harness.device(description="原图").wait(timeout=5):
        if not harness.device(text="原图").wait(timeout=2):
            raise AssertionError("attachment panel does not expose Original image")


def crop_hashes(harness: P1Harness, count: int = 5) -> list[str]:
    values: list[str] = []
    width, height = harness.device.window_size()
    box = (0, int(height * 0.18), width, int(height * 0.86))
    for _ in range(count):
        image = harness.device.screenshot().crop(box)
        data = io.BytesIO()
        image.save(data, format="PNG")
        values.append(hashlib.sha256(data.getvalue()).hexdigest())
        time.sleep(0.22)
    return values


def tap_latest_media_bubble(harness: P1Harness) -> None:
    """Tap the lowest sizeable message bubble, including custom GIF views.

    AnimatedGifImage is exposed by Flutter semantics as android.view.View,
    while static images are exposed as android.widget.ImageView. Restricting
    this lookup to ImageView can therefore open the previous static image.
    """
    width, height = harness.device.window_size()
    candidates = [
        item
        for item in harness.nodes()
        if item["class"] in {"android.view.View", "android.widget.ImageView"}
        and item["clickable"]
        and item["right"] - item["left"] >= 150
        and item["bottom"] - item["top"] >= 150
        and item["right"] - item["left"] < width * 0.9
        and item["bottom"] < height * 0.94
    ]
    if not candidates:
        raise RuntimeError("received GIF bubble not found")
    target = max(candidates, key=lambda item: (item["bottom"], item["top"]))
    harness.device.click(
        (target["left"] + target["right"]) // 2,
        (target["top"] + target["bottom"]) // 2,
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", required=True)
    parser.add_argument("--run-dir", required=True)
    parser.add_argument("--adb", required=True)
    parser.add_argument("--sender", required=True)
    parser.add_argument("--receiver", required=True)
    parser.add_argument("--credentials", required=True)
    parser.add_argument("--original-source", required=True)
    parser.add_argument("--gif-source", required=True)
    parser.add_argument("--apk-sha256", required=True)
    parser.add_argument("--package", default="com.genericim.ma100")
    parser.add_argument("--base", default="https://api.example.com/api/v1")
    args = parser.parse_args()

    repo = Path(args.repo).resolve()
    run_dir = Path(args.run_dir).resolve()
    run_dir.mkdir(parents=True, exist_ok=True)
    credential = json.loads(Path(args.credentials).read_text(encoding="utf-8-sig"))
    token = str(credential["token"])
    sender = P1Harness(repo, run_dir / args.sender, args.adb, args.sender, args.package)
    receiver = P1Harness(repo, run_dir / args.receiver, args.adb, args.receiver, args.package)
    chat_id = find_private_chat(args.base, token, "smoke_bob")
    cases: list[dict] = []

    def ids() -> set[str]:
        return {str(item.get("msg_id")) for item in list_messages(args.base, token, chat_id, 100)}

    try:
        evidence = sender.open_private("smoke_bob", "im144")
        open_attachment(sender)
        evidence += sender.snapshot("im144-original-option-off")
        original = sender.device(description="原图")
        if not original.click_exists(timeout=2):
            sender.device(text="原图").click()
        time.sleep(1)
        evidence += sender.snapshot("im144-original-option-on")
        before = ids()
        album = sender.device(description="相册")
        if not album.click_exists(timeout=2):
            sender.device(text="相册").click()
        select_document(sender, "P2B2_ORIGINAL.png")
        message = wait_for_new_image(args.base, token, chat_id, before)
        url = str(((message.get("content") or {}).get("media") or {}).get("url") or "")
        if not url:
            raise AssertionError("original image server message has no media URL")
        remote = urlopen(url, timeout=30).read()
        source = Path(args.original_source).read_bytes()
        if hashlib.sha256(remote).digest() != hashlib.sha256(source).digest():
            raise AssertionError("original image bytes changed during upload")
        audit = run_dir / "im144-original-hash-audit.json"
        audit.write_text(
            json.dumps(
                {
                    "source_size": len(source),
                    "remote_size": len(remote),
                    "sha256": hashlib.sha256(source).hexdigest(),
                    "msg_id": message.get("msg_id"),
                    "url": url,
                },
                ensure_ascii=False,
                indent=2,
            ),
            encoding="utf-8",
        )
        evidence += sender.snapshot("im144-original-sent")
        evidence.append(rel(audit, repo))
        cases.append({"case_id": "IM-144", "status": "PASS", "detail": "Original switch is visible; uploaded bytes and SHA-256 equal the source PNG.", "evidence": evidence})
    except Exception as exc:
        cases.append({"case_id": "IM-144", "status": "FAIL", "detail": str(exc), "evidence": sender.snapshot("im144-failed")})

    try:
        evidence = sender.open_private("smoke_bob", "im147")
        open_attachment(sender)
        before = ids()
        album = sender.device(description="相册")
        if not album.click_exists(timeout=2):
            sender.device(text="相册").click()
        select_document(sender, "P2B2_ANIMATED.gif")
        message = wait_for_new_image(args.base, token, chat_id, before)
        url = str(((message.get("content") or {}).get("media") or {}).get("url") or "")
        remote = urlopen(url, timeout=30).read()
        source = Path(args.gif_source).read_bytes()
        if hashlib.sha256(remote).digest() != hashlib.sha256(source).digest():
            raise AssertionError("GIF bytes changed during upload")
        evidence += receiver.open_private(str(credential["username"]), "im147-receiver")
        time.sleep(4)
        bubble_hashes = crop_hashes(receiver)
        evidence += receiver.snapshot("im147-bubble-animated")
        if len(set(bubble_hashes)) < 2:
            raise AssertionError("GIF bubble remained on one frame")
        tap_latest_media_bubble(receiver)
        time.sleep(3)
        preview_hashes = crop_hashes(receiver)
        evidence += receiver.snapshot("im147-preview-animated")
        if len(set(preview_hashes)) < 2:
            raise AssertionError("full-screen GIF preview remained on one frame")
        audit = run_dir / "im147-frame-hash-audit.json"
        audit.write_text(json.dumps({"source_sha256": hashlib.sha256(source).hexdigest(), "remote_sha256": hashlib.sha256(remote).hexdigest(), "bubble_frame_hashes": bubble_hashes, "preview_frame_hashes": preview_hashes, "msg_id": message.get("msg_id")}, indent=2), encoding="utf-8")
        evidence.append(rel(audit, repo))
        cases.append({"case_id": "IM-147", "status": "PASS", "detail": "GIF source bytes were preserved; bubble and full-screen preview produced changing frame hashes.", "evidence": evidence})
    except Exception as exc:
        cases.append({"case_id": "IM-147", "status": "FAIL", "detail": str(exc), "evidence": receiver.snapshot("im147-failed")})

    payload = {"environment": {"finished_at": datetime.now().astimezone().isoformat(timespec="seconds"), "devices": [args.sender, args.receiver], "apk_sha256": args.apk_sha256}, "cases": cases}
    (run_dir / "p2b2-validation-results.json").write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    lines = ["# P2-B2 图片/GIF 真机验证报告", "", "| 用例 | 状态 | 结论 |", "|---|---|---|"]
    lines.extend(f"| {item['case_id']} | {item['status']} | {item['detail']} |" for item in cases)
    (run_dir / "P2B2_REAL_DEVICE_VALIDATION_REPORT.md").write_text("\n".join(lines), encoding="utf-8")
    for item in cases:
        print(f"[P2-B2] {item['case_id']}: {item['status']} - {item['detail']}", flush=True)
    return 1 if any(item["status"] != "PASS" for item in cases) else 0


if __name__ == "__main__":
    raise SystemExit(main())
