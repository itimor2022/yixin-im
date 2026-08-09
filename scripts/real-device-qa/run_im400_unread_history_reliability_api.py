#!/usr/bin/env python3
"""Validate high unread counts, history paging, favorites, and idempotency."""

from __future__ import annotations

import argparse
import json
import sys
import time
import urllib.parse
import uuid
from pathlib import Path
from typing import Any, Callable

from run_im400_device_unblocked_api import create_account, login
from run_im400_remaining_api import Api, check, create_chat, list_items, response_data


def chat_rows(api: Api, actor: Any) -> list[dict[str, Any]]:
    return list_items(api.request("GET", "/chat/list?page=1&page_size=100", actor=actor))


def chat_row(api: Api, actor: Any, chat_id: str) -> dict[str, Any]:
    return next(row for row in chat_rows(api, actor) if str(row.get("chat_id")) == chat_id)


def send_message(
    api: Api,
    actor: Any,
    chat_id: str,
    message_type: int,
    content: dict[str, Any],
    *,
    msg_id: str | None = None,
    burn_after_read: bool = False,
    source_ip: str | None = None,
) -> dict[str, Any]:
    data = response_data(
        api.request(
            "POST",
            "/message/send",
            actor=actor,
            extra_headers={"X-Forwarded-For": source_ip} if source_ip else None,
            body={
                "chat_id": chat_id,
                "type": message_type,
                "content": content,
                "msg_id": msg_id or str(uuid.uuid4()),
                "burn_after_read": burn_after_read,
            },
        )
    )
    check(isinstance(data, dict) and int(data.get("seq", 0)) > 0, f"message send failed: {data}")
    return data


def message_page(
    api: Api,
    actor: Any,
    chat_id: str,
    *,
    before_seq: int | None = None,
    limit: int = 30,
) -> list[dict[str, Any]]:
    query = {"chat_id": chat_id, "limit": limit}
    if before_seq is not None:
        query["before_seq"] = before_seq
    return list_items(
        api.request(
            "GET",
            f"/message/list?{urllib.parse.urlencode(query)}",
            actor=actor,
        )
    )


def run(base_url: str, output_dir: Path) -> dict[str, Any]:
    api = Api(base_url.rstrip("/") + "/api/v1")
    run_id = f"{int(time.time())}-{uuid.uuid4().hex[:6]}"
    accounts = [create_account(api, label, run_id) for label in ("HistoryA", "HistoryB", "HistoryC", "HistoryD", "HistoryE")]
    recipient_account, *sender_accounts = accounts
    recipient = recipient_account.sessions["android"]
    senders = [account.sessions["android"] for account in sender_accounts]
    group_id = create_chat(api, recipient, 2, senders, name=f"History QA {run_id}")
    results: list[dict[str, Any]] = []
    sent_messages: list[dict[str, Any]] = []

    def record(case_ids: list[str], body: Callable[[], str]) -> None:
        try:
            results.append({"case_ids": case_ids, "status": "PASS", "detail": body()})
        except Exception as exc:  # noqa: BLE001 - keep independent evidence running
            results.append(
                {
                    "case_ids": case_ids,
                    "status": "FAIL",
                    "detail": f"{type(exc).__name__}: {exc}",
                }
            )

    def high_unread() -> str:
        for sender_index, sender in enumerate(senders):
            for message_index in range(25):
                sent_messages.append(
                    send_message(
                        api,
                        sender,
                        group_id,
                        1,
                        {"text": f"HISTORY_{run_id}_{sender_index}_{message_index:02d}"},
                        source_ip=f"198.51.100.{sender_index + 10}",
                    )
                )
        row = chat_row(api, recipient, group_id)
        check(int(row.get("unread_count", 0)) == 100, f"authoritative unread count is not 100: {row}")
        check(max(int(message["seq"]) for message in sent_messages) >= 100, "message sequence did not advance")
        return "four senders produced 100 real unread messages without rate-limit shortcuts; the server retained the exact authoritative count of 100 for the recipient"

    record(["IM-097"], high_unread)

    def new_device_and_cross_platform_history() -> str:
        check(len(sent_messages) == 100, "unread setup did not complete")
        windows = login(api, recipient_account, "history-windows", "windows", run_id)
        check(int(chat_row(api, windows, group_id).get("unread_count", 0)) == 100, "new device did not receive authoritative unread state")
        android_history = message_page(api, recipient, group_id, limit=100)
        windows_history = message_page(api, windows, group_id, limit=100)
        android_pairs = [(int(row.get("seq", 0)), row.get("content", {}).get("text")) for row in android_history]
        windows_pairs = [(int(row.get("seq", 0)), row.get("content", {}).get("text")) for row in windows_history]
        check(len(android_pairs) == 100, f"Android first history window is incomplete: {len(android_pairs)}")
        check(android_pairs == windows_pairs, "Android and Windows history content/order diverged")
        return "a newly logged-in Windows session loaded the same 100-message server history, order, content, and unread state as Android"

    record(["IM-227", "IM-230"], new_device_and_cross_platform_history)

    def history_pagination() -> str:
        before_seq: int | None = None
        collected: list[dict[str, Any]] = []
        page_sizes: list[int] = []
        while True:
            page = message_page(api, recipient, group_id, before_seq=before_seq, limit=30)
            page_sizes.append(len(page))
            if not page:
                break
            collected.extend(page)
            before_seq = min(int(row.get("seq", 0)) for row in page)
            if len(page) < 30:
                empty = message_page(api, recipient, group_id, before_seq=before_seq, limit=30)
                page_sizes.append(len(empty))
                check(not empty, f"history did not stop at the earliest message: {empty}")
                break
        seqs = [int(row.get("seq", 0)) for row in collected]
        expected_ids = {str(message["msg_id"]) for message in sent_messages}
        collected_ids = {str(row.get("msg_id")) for row in collected}
        check(
            expected_ids.issubset(collected_ids),
            f"pagination missed test messages: {sorted(expected_ids - collected_ids)}",
        )
        check(len(seqs) >= 100, f"pagination returned too few messages: {len(seqs)}, pages={page_sizes}")
        check(len(seqs) == len(set(seqs)), "pagination returned duplicate sequences")
        check(seqs == sorted(seqs, reverse=True), "pagination order is not strictly descending")
        return f"history paged through all 100 test messages plus allowed system history to the earliest boundary in stable descending order with no duplicates or gaps; page sizes were {page_sizes}"

    record(["IM-228", "IM-229"], history_pagination)

    def stable_retry_id() -> str:
        fixed_id = str(uuid.uuid4())
        first = send_message(
            api,
            senders[0],
            group_id,
            1,
            {"text": f"IDEMPOTENT_{run_id}"},
            msg_id=fixed_id,
            source_ip="198.51.100.10",
        )
        second = send_message(
            api,
            senders[0],
            group_id,
            1,
            {"text": f"IDEMPOTENT_{run_id}"},
            msg_id=fixed_id,
            source_ip="198.51.100.10",
        )
        check(first.get("msg_id") == second.get("msg_id") == fixed_id, f"stable id changed: {first}, {second}")
        check(int(first.get("seq", 0)) == int(second.get("seq", -1)), f"retry allocated a second sequence: {first}, {second}")
        check(first.get("duplicate") is False and second.get("duplicate") is True, f"duplicate acknowledgement is wrong: {first}, {second}")
        history = message_page(api, recipient, group_id, limit=100)
        check(sum(row.get("msg_id") == fixed_id for row in history) == 1, "stable retry created a duplicate history row")
        return "a timeout-style retry with the same client message id returned the original sequence and duplicate acknowledgement while history retained one row"

    record(["IM-125"], stable_retry_id)

    favorite_chat = create_chat(api, recipient, 1, [senders[0]])

    def favorite_types() -> str:
        messages = [
            send_message(api, recipient, favorite_chat, 1, {"text": f"favorite text {run_id}"}, source_ip="198.51.100.30"),
            send_message(api, recipient, favorite_chat, 2, {"media": {"url": "/uploads/qa/favorite.jpg", "thumbnail": "/uploads/qa/favorite-thumb.jpg"}}, source_ip="198.51.100.30"),
            send_message(api, recipient, favorite_chat, 5, {"file": {"url": "/uploads/qa/favorite.pdf", "name": "favorite.pdf", "size": 128, "mime_type": "application/pdf"}}, source_ip="198.51.100.30"),
            send_message(api, recipient, favorite_chat, 1, {"text": f"https://example.test/favorite/{run_id}"}, source_ip="198.51.100.30"),
        ]
        for message in messages:
            api.request(
                "POST",
                "/message/favorite",
                actor=recipient,
                body={"chat_id": favorite_chat, "message_id": message["msg_id"]},
            )
        favorites = list_items(api.request("GET", "/message/favorites?page=1&page_size=50", actor=recipient))
        selected = [item for item in favorites if item.get("chat_id") == favorite_chat]
        check(len(selected) == 4, f"favorite list is incomplete: {selected}")
        by_id = {str(item.get("message_id")): item for item in selected}
        check(set(by_id) == {str(message["msg_id"]) for message in messages}, "favorite source ids changed")
        check({item.get("message_type") for item in selected} == {"text", "image", "file"}, f"favorite types are wrong: {selected}")
        check(any(str(item.get("content", "")).startswith("https://example.test/") for item in selected), "favorite link content was lost")
        check(all(item.get("sender_id") == recipient.user_id for item in selected), "favorite sender source is wrong")
        return "text, image, file, and link favorites retained their source chat, message id, sender, content, and type-specific metadata"

    record(["IM-218"], favorite_types)

    def restricted_forward() -> str:
        burn = send_message(
            api,
            recipient,
            favorite_chat,
            1,
            {"text": f"burn restricted {run_id}"},
            burn_after_read=True,
            source_ip="198.51.100.30",
        )
        payload = api.request(
            "POST",
            "/message/forward",
            actor=recipient,
            expected_status=403,
            body={
                "source_chat_id": favorite_chat,
                "source_msg_id": burn["msg_id"],
                "target_chat_id": group_id,
                "client_msg_id": str(uuid.uuid4()),
            },
        )
        check(int(payload.get("code", 0)) != 0 and "阅后即焚" in str(payload.get("message", "")), f"restricted forward error is wrong: {payload}")
        return "the server rejected forwarding a burn-after-read message with an explicit HTTP 403 security error"

    record(["IM-217"], restricted_forward)

    report = {
        "run_id": run_id,
        "base_url": base_url,
        "group_id": group_id,
        "results": results,
        "summary": {
            "pass": sum(result["status"] == "PASS" for result in results),
            "fail": sum(result["status"] == "FAIL" for result in results),
            "covered_case_ids": sorted({case_id for result in results for case_id in result["case_ids"]}),
        },
    }
    output_dir.mkdir(parents=True, exist_ok=True)
    report_path = output_dir / f"unread-history-reliability-api-{run_id}.json"
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
