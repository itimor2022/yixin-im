#!/usr/bin/env python3
"""Validate persisted mention reminders and text length limits locally."""

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


def chat_row(api: Api, actor: Actor, chat_id: str) -> dict[str, Any]:
    rows = list_items(api.request("GET", "/chat/list?page=1&page_size=100", actor=actor))
    return next(row for row in rows if str(row.get("chat_id")) == chat_id)


def run(base_url: str, output_dir: Path) -> dict[str, Any]:
    api = Api(base_url.rstrip("/") + "/api/v1")
    run_id = f"{int(time.time())}-{uuid.uuid4().hex[:6]}"
    a, b, c = [create_actor(api, label, run_id) for label in ("MentionA", "MentionB", "MentionC")]
    group_id = create_chat(api, a, 2, [b, c], name=f"Mention QA {run_id}")
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

    def persisted_mention() -> str:
        sent = response_data(
            api.request(
                "POST",
                "/message/send",
                actor=a,
                body={
                    "chat_id": group_id,
                    "type": 1,
                    "content": {"text": f"@MentionB persisted reminder {run_id}"},
                    "msg_id": str(uuid.uuid4()),
                    "mentions": [b.user_id],
                },
            )
        )
        check(isinstance(sent, dict) and int(sent.get("seq", 0)) > 0, f"mention send failed: {sent}")
        b_row = chat_row(api, b, group_id)
        c_row = chat_row(api, c, group_id)
        a_row = chat_row(api, a, group_id)
        check(b_row.get("has_mention") is True, f"mentioned recipient lost reminder: {b_row}")
        check(int(b_row.get("unread_count", 0)) > 0, f"mentioned recipient has no unread count: {b_row}")
        check(c_row.get("has_mention") is False, f"unmentioned recipient received reminder: {c_row}")
        check(a_row.get("has_mention") is False, f"sender received own reminder: {a_row}")

        api.request(
            "POST",
            "/message/read",
            actor=b,
            body={"chat_id": group_id, "msg_seq": int(sent["seq"])},
        )
        reloaded = chat_row(api, b, group_id)
        check(reloaded.get("has_mention") is False, f"read did not clear reminder: {reloaded}")
        check(int(reloaded.get("unread_count", -1)) == 0, f"read did not clear unread count: {reloaded}")
        return "a targeted @ reminder persisted in a fresh chat-list response only for the recipient and cleared after the read API"

    record(["IM-093"], persisted_mention)

    def text_boundaries() -> str:
        accepted_text = "界" * 5000
        accepted = response_data(
            api.request(
                "POST",
                "/message/send",
                actor=a,
                body={
                    "chat_id": group_id,
                    "type": 1,
                    "content": {"text": accepted_text},
                    "msg_id": str(uuid.uuid4()),
                },
            )
        )
        check(isinstance(accepted, dict) and int(accepted.get("seq", 0)) > 0, "5000-character message was rejected")

        rejected = api.request(
            "POST",
            "/message/send",
            actor=a,
            expected_status=400,
            body={
                "chat_id": group_id,
                "type": 1,
                "content": {"text": "界" * 5001},
                "msg_id": str(uuid.uuid4()),
            },
        )
        check(int(rejected.get("code", 0)) != 0, f"5001-character message unexpectedly succeeded: {rejected}")
        check("5000" in str(rejected.get("message", "")), f"length error is unclear: {rejected}")

        edit_rejected = api.request(
            "POST",
            "/message/edit",
            actor=a,
            expected_status=400,
            body={
                "chat_id": group_id,
                "msg_id": str(accepted["msg_id"]),
                "content": "界" * 5001,
            },
        )
        check(int(edit_rejected.get("code", 0)) != 0, f"5001-character edit unexpectedly succeeded: {edit_rejected}")
        return "5000 Unicode characters sent successfully; 5001-character sends and edits returned an explicit HTTP 400 limit error"

    record(["IM-103"], text_boundaries)

    report = {
        "run_id": run_id,
        "base_url": base_url,
        "actors": [actor.user_id for actor in (a, b, c)],
        "chat_id": group_id,
        "results": results,
        "summary": {
            "pass": sum(result["status"] == "PASS" for result in results),
            "fail": sum(result["status"] == "FAIL" for result in results),
            "covered_case_ids": sorted({case_id for result in results for case_id in result["case_ids"]}),
        },
    }
    output_dir.mkdir(parents=True, exist_ok=True)
    report_path = output_dir / f"mention-text-limit-api-{run_id}.json"
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
