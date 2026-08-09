#!/usr/bin/env python3
"""Validate message search filters and authorization against local Docker."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import sys
import time
import urllib.parse
import uuid
from pathlib import Path
from typing import Any

from run_im400_remaining_api import (
    Actor,
    Api,
    check,
    create_actor,
    create_chat,
    list_items,
    response_data,
    send_text,
)


def send_image(api: Api, actor: Actor, chat_id: str, caption: str) -> dict[str, Any]:
    payload = api.request(
        "POST",
        "/message/send",
        actor=actor,
        body={
            "chat_id": chat_id,
            "type": 2,
            "content": {
                "text": caption,
                "media": {
                    "url": "/uploads/qa/search-filter-image.png",
                    "thumbnail": "/uploads/qa/search-filter-image-thumb.png",
                    "width": 32,
                    "height": 32,
                    "size": 128,
                    "mime_type": "image/png",
                },
            },
            "msg_id": str(uuid.uuid4()),
        },
    )
    data = response_data(payload)
    check(isinstance(data, dict), f"image response is invalid: {payload}")
    return data


def search(
    api: Api,
    actor: Actor,
    chat_id: str,
    **params: Any,
) -> list[dict[str, Any]]:
    query = urllib.parse.urlencode(
        {
            key: value.isoformat().replace("+00:00", "Z")
            if isinstance(value, dt.datetime)
            else value
            for key, value in params.items()
            if value is not None and value != ""
        }
    )
    payload = api.request("GET", f"/chat/{chat_id}/search?{query}", actor=actor)
    data = response_data(payload)
    if isinstance(data, dict) and data.get("list") is None:
        return []
    return list_items(payload)


def message_ids(items: list[dict[str, Any]]) -> set[str]:
    return {str(item.get("msg_id")) for item in items}


def run(base_url: str, output_dir: Path) -> dict[str, Any]:
    api = Api(base_url.rstrip("/") + "/api/v1")
    run_id = f"{int(time.time())}-{uuid.uuid4().hex[:6]}"
    a, b, c = [create_actor(api, label, run_id) for label in ("A", "B", "C")]
    group_id = create_chat(api, a, 2, [b], f"SEARCH_SECURITY_{run_id}"[:32])
    results: list[dict[str, Any]] = []

    def passed(case_ids: list[str], detail: str) -> None:
        results.append({"case_ids": case_ids, "status": "PASS", "detail": detail})

    shared_keyword = f"FILTER_SHARED_{run_id}"
    from_a = send_text(api, a, group_id, f"{shared_keyword}_FROM_A")
    from_b = send_text(api, b, group_id, f"{shared_keyword}_FROM_B")
    image = send_image(api, b, group_id, f"{shared_keyword}_IMAGE")

    by_a = search(api, a, group_id, keyword=shared_keyword, sender_id=a.user_id)
    check(message_ids(by_a) == {str(from_a["msg_id"])}, f"sender A filter leaked other messages: {by_a}")
    by_b = search(api, a, group_id, keyword=shared_keyword, sender_id=b.user_id)
    check(
        message_ids(by_b) == {str(from_b["msg_id"]), str(image["msg_id"])},
        f"sender B filter missed or leaked messages: {by_b}",
    )
    passed(["IM-233"], "sender filter returned only messages authored by the selected chat member")

    now = dt.datetime.now(dt.timezone.utc)
    current = search(
        api,
        a,
        group_id,
        keyword=shared_keyword,
        start_at=now - dt.timedelta(days=1),
        end_at=now + dt.timedelta(days=1),
    )
    check(
        {str(from_a["msg_id"]), str(from_b["msg_id"]), str(image["msg_id"])}.issubset(message_ids(current)),
        f"current date range missed seeded messages: {current}",
    )
    old_start = dt.datetime(2000, 1, 1, tzinfo=dt.timezone.utc)
    old_end = dt.datetime(2000, 1, 2, tzinfo=dt.timezone.utc)
    old = search(api, a, group_id, keyword=shared_keyword, start_at=old_start, end_at=old_end)
    check(not old, f"past date range returned current messages: {old}")
    passed(["IM-234"], "RFC3339 start/end boundaries included current messages and excluded them from a past range")

    images = search(api, a, group_id, message_type=2)
    check(str(image["msg_id"]) in message_ids(images), f"image type filter missed target: {images}")
    check(all(int(item.get("type", 0)) == 2 for item in images), f"image type filter leaked other types: {images}")
    text = search(api, a, group_id, keyword=shared_keyword, message_type=1)
    check(
        message_ids(text) == {str(from_a["msg_id"]), str(from_b["msg_id"])},
        f"text type filter was inaccurate: {text}",
    )
    passed(["IM-235"], "message type filter supported filter-only image search and keyword-plus-text search")

    hidden_text = f"DELETE_SEARCH_PRIVACY_{run_id}"
    hidden = send_text(api, a, group_id, hidden_text)
    api.request(
        "POST",
        "/message/delete",
        actor=b,
        body={"chat_id": group_id, "msg_id": hidden["msg_id"]},
    )
    check(not search(api, b, group_id, keyword=hidden_text), "per-user deleted message reappeared in B search")
    check(
        str(hidden["msg_id"]) in message_ids(search(api, a, group_id, keyword=hidden_text)),
        "B's local delete incorrectly hid the message from A",
    )
    passed(["IM-239"], "search honored per-user deletion without changing another member's visibility")

    search_query = urllib.parse.urlencode({"keyword": shared_keyword})
    api.request("GET", f"/chat/{group_id}/search?{search_query}", actor=c, expected_status=403)
    list_query = urllib.parse.urlencode({"chat_id": group_id, "before_seq": 0, "limit": 20})
    api.request("GET", f"/message/list?{list_query}", actor=c, expected_status=403)
    detail_query = urllib.parse.urlencode({"chat_id": group_id, "msg_id": from_a["msg_id"]})
    api.request("GET", f"/message/detail?{detail_query}", actor=c, expected_status=403)
    api.request(
        "POST",
        "/message/delete",
        actor=c,
        body={"chat_id": group_id, "msg_id": from_a["msg_id"]},
        expected_status=403,
    )
    passed(["IM-388"], "non-member was denied search, history, detail and per-user delete mutation")

    api.request(
        "PUT",
        f"/chat/{group_id}",
        actor=c,
        body={"name": "UNAUTHORIZED"},
        expected_status=403,
    )
    api.request(
        "PUT",
        f"/chat/{group_id}/members/{b.user_id}/role",
        actor=c,
        body={"role": 1},
        expected_status=403,
    )
    api.request(
        "DELETE",
        f"/chat/{group_id}/members/{b.user_id}",
        actor=c,
        expected_status=403,
    )
    passed(["IM-389"], "non-member was denied group profile, role and membership management mutations")

    report = {
        "run_id": run_id,
        "base_url": base_url,
        "actors": [{"name": actor.name, "user_id": actor.user_id} for actor in (a, b, c)],
        "chat_id": group_id,
        "results": results,
        "summary": {
            "passed_assertion_groups": len(results),
            "covered_case_ids": sorted({case_id for result in results for case_id in result["case_ids"]}),
        },
    }
    output_dir.mkdir(parents=True, exist_ok=True)
    report_path = output_dir / f"search-security-api-{run_id}.json"
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    report["report_path"] = str(report_path)
    return report


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", default="http://127.0.0.1:8080")
    parser.add_argument("--output-dir", required=True)
    args = parser.parse_args()
    try:
        report = run(args.base_url, Path(args.output_dir).resolve())
    except Exception as error:  # noqa: BLE001
        print(json.dumps({"status": "FAIL", "error": str(error)}, ensure_ascii=False, indent=2))
        return 1
    print(json.dumps({"status": "PASS", **report}, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
