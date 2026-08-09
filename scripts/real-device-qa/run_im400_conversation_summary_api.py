#!/usr/bin/env python3
"""Validate conversation ordering, unread toggles, and list previews."""

from __future__ import annotations

import argparse
import json
import sys
import time
import uuid
from pathlib import Path
from typing import Any, Callable

from run_im400_remaining_api import (
    Actor,
    Api,
    check,
    create_actor,
    create_chat,
    list_items,
    response_data,
)


def chat_rows(api: Api, actor: Actor) -> list[dict[str, Any]]:
    return list_items(api.request("GET", "/chat/list?page=1&page_size=100", actor=actor))


def chat_row(api: Api, actor: Actor, chat_id: str) -> dict[str, Any]:
    return next(row for row in chat_rows(api, actor) if str(row.get("chat_id")) == chat_id)


def send_message(
    api: Api,
    actor: Actor,
    chat_id: str,
    message_type: int,
    content: dict[str, Any],
) -> dict[str, Any]:
    data = response_data(
        api.request(
            "POST",
            "/message/send",
            actor=actor,
            body={
                "chat_id": chat_id,
                "type": message_type,
                "content": content,
                "msg_id": str(uuid.uuid4()),
            },
        )
    )
    check(isinstance(data, dict) and int(data.get("seq", 0)) > 0, f"message send failed: {data}")
    return data


def run(base_url: str, output_dir: Path) -> dict[str, Any]:
    api = Api(base_url.rstrip("/") + "/api/v1")
    run_id = f"{int(time.time())}-{uuid.uuid4().hex[:6]}"
    a, b, c, d = [create_actor(api, label, run_id) for label in ("ListA", "ListB", "ListC", "ListD")]
    chat_ab = create_chat(api, a, 1, [b])
    chat_ac = create_chat(api, a, 1, [c])
    chat_ad = create_chat(api, a, 1, [d])
    results: list[dict[str, Any]] = []

    def record(case_ids: list[str], body: Callable[[], str]) -> None:
        try:
            results.append({"case_ids": case_ids, "status": "PASS", "detail": body()})
        except Exception as exc:  # noqa: BLE001 - retain all case evidence
            results.append(
                {
                    "case_ids": case_ids,
                    "status": "FAIL",
                    "detail": f"{type(exc).__name__}: {exc}",
                }
            )

    latest_ab: dict[str, Any] = {}

    def multiple_pin_ordering() -> str:
        for chat_id in (chat_ab, chat_ac):
            data = response_data(api.request("POST", f"/chat/{chat_id}/pin", actor=a, body={}))
            check(isinstance(data, dict) and data.get("is_pinned") is True, f"pin failed: {data}")

        time.sleep(1.1)
        send_message(api, b, chat_ab, 1, {"text": f"AB first {run_id}"})
        time.sleep(1.1)
        send_message(api, c, chat_ac, 1, {"text": f"AC second {run_id}"})
        time.sleep(1.1)
        send_message(api, d, chat_ad, 1, {"text": f"AD newest unpinned {run_id}"})

        rows = chat_rows(api, a)
        ids = [str(row.get("chat_id")) for row in rows]
        check(ids[:2] == [chat_ac, chat_ab], f"pinned chats were not sorted by latest message: {ids[:3]}")
        check(ids.index(chat_ad) > 1, f"newer unpinned chat escaped the pinned section: {ids[:3]}")

        time.sleep(1.1)
        latest_ab.update(send_message(api, b, chat_ab, 1, {"text": f"AB newest pinned {run_id}"}))
        reordered = [str(row.get("chat_id")) for row in chat_rows(api, a)]
        check(reordered[:2] == [chat_ab, chat_ac], f"pinned order did not react to a new message: {reordered[:3]}")
        check(reordered.index(chat_ad) > 1, f"unpinned chat entered pinned section after reorder: {reordered[:3]}")
        return "two pinned conversations stayed ahead of a newer unpinned chat and reordered by the latest message within the pinned section"

    record(["IM-084"], multiple_pin_ordering)

    def toggle_unread() -> str:
        check(latest_ab, "pin-order setup did not produce the AB message")
        api.request(
            "POST",
            "/message/read",
            actor=a,
            body={"chat_id": chat_ab, "msg_seq": int(latest_ab["seq"])},
        )
        before_rows = chat_rows(api, a)
        before_total = sum(int(row.get("unread_count", 0)) for row in before_rows)
        check(int(next(row for row in before_rows if row.get("chat_id") == chat_ab).get("unread_count", -1)) == 0, "setup chat is not read")

        marked = response_data(api.request("POST", f"/chat/{chat_ab}/toggle-unread", actor=a, body={}))
        check(isinstance(marked, dict) and int(marked.get("unread_count", 0)) == 1, f"mark-unread response is invalid: {marked}")
        marked_rows = chat_rows(api, a)
        marked_total = sum(int(row.get("unread_count", 0)) for row in marked_rows)
        marked_row = next(row for row in marked_rows if row.get("chat_id") == chat_ab)
        check(int(marked_row.get("unread_count", 0)) == 1, f"mark-unread did not persist: {marked_row}")
        check(marked_row.get("has_mention") is False, f"manual unread incorrectly created an @ reminder: {marked_row}")
        check(marked_total == before_total + 1, f"aggregate unread count did not increase by one: {before_total} -> {marked_total}")

        cleared = response_data(api.request("POST", f"/chat/{chat_ab}/toggle-unread", actor=a, body={}))
        check(isinstance(cleared, dict) and int(cleared.get("unread_count", -1)) == 0, f"clear-unread response is invalid: {cleared}")
        after_total = sum(int(row.get("unread_count", 0)) for row in chat_rows(api, a))
        check(after_total == before_total, f"aggregate unread count did not return to baseline: {before_total} -> {after_total}")
        return "manual mark-unread persisted one unread without creating an @ reminder; the aggregate unread total increased by one and returned after toggling read"

    record(["IM-087"], toggle_unread)

    def revoked_last_preview() -> str:
        sent = send_message(api, a, chat_ad, 1, {"text": f"revoke last {run_id}"})
        sender_before = chat_row(api, a, chat_ad)
        recipient_before = chat_row(api, d, chat_ad)
        api.request(
            "POST",
            "/message/revoke",
            actor=a,
            body={"chat_id": chat_ad, "msg_id": sent["msg_id"]},
        )
        sender_after = chat_row(api, a, chat_ad)
        recipient_after = chat_row(api, d, chat_ad)
        check(sender_after.get("last_msg_text") == "你撤回了一条消息", f"sender revoke preview is wrong: {sender_after}")
        check(recipient_after.get("last_msg_text") == "有人撤回了一条消息", f"recipient revoke preview is wrong: {recipient_after}")
        check(sender_after.get("last_msg_time") == sender_before.get("last_msg_time"), "sender revoke changed the message time")
        check(recipient_after.get("last_msg_time") == recipient_before.get("last_msg_time"), "recipient revoke changed the message time")
        check(int(sender_after.get("last_msg_seq", 0)) == int(sent["seq"]), "revoke preview lost the last sequence")
        return "revoking the last message produced role-appropriate summaries for both users while retaining the original message time and sequence"

    record(["IM-094"], revoked_last_preview)

    def media_previews() -> str:
        cases = [
            (2, {"media": {"url": "/uploads/qa/image.jpg", "thumbnail": "/uploads/qa/image-thumb.jpg", "width": 640, "height": 480}}, "[图片]", "/uploads/qa/image-thumb.jpg"),
            (4, {"voice": {"url": "/uploads/qa/voice.m4a", "duration": 3, "size": 128}}, "[语音]", ""),
            (3, {"media": {"url": "/uploads/qa/video.mp4", "thumbnail": "/uploads/qa/video-thumb.jpg", "duration": 4}}, "[视频]", "/uploads/qa/video-thumb.jpg"),
            (5, {"file": {"url": "/uploads/qa/report.pdf", "name": "report.pdf", "size": 256, "mime_type": "application/pdf"}}, "[文件]", ""),
        ]
        observed: list[tuple[int, str]] = []
        for message_type, content, expected_text, expected_media in cases:
            send_message(api, a, chat_ab, message_type, content)
            row = chat_row(api, b, chat_ab)
            check(int(row.get("last_msg_type", 0)) == message_type, f"preview type mismatch for {message_type}: {row}")
            check(row.get("last_msg_text") == expected_text, f"preview text mismatch for {message_type}: {row}")
            check(str(row.get("last_msg_media_url") or "") == expected_media, f"preview media mismatch for {message_type}: {row}")
            observed.append((message_type, expected_text))
        return f"image, voice, video, and file messages produced the expected type-specific list summaries and media URLs: {observed}"

    record(["IM-095"], media_previews)

    report = {
        "run_id": run_id,
        "base_url": base_url,
        "actors": [actor.user_id for actor in (a, b, c, d)],
        "chat_ids": {"ab": chat_ab, "ac": chat_ac, "ad": chat_ad},
        "results": results,
        "summary": {
            "pass": sum(result["status"] == "PASS" for result in results),
            "fail": sum(result["status"] == "FAIL" for result in results),
            "covered_case_ids": sorted({case_id for result in results for case_id in result["case_ids"]}),
        },
    }
    output_dir.mkdir(parents=True, exist_ok=True)
    report_path = output_dir / f"conversation-summary-api-{run_id}.json"
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    report["report_path"] = str(report_path)
    return report


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", default="http://127.0.0.1:8080")
    parser.add_argument("--output-dir", required=True)
    args = parser.parse_args()
    report = run(args.base_url, Path(args.output_dir).resolve())
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0 if report["summary"]["fail"] == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
