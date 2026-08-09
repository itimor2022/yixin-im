#!/usr/bin/env python3
"""Validate user, group, channel and message report contracts."""

from __future__ import annotations

import argparse
import json
import sys
import time
import uuid
from pathlib import Path
from typing import Any

from run_im400_remaining_api import (
    Actor,
    Api,
    ApiError,
    create_actor,
    create_chat,
    response_data,
    send_text,
)


def report(
    api: Api,
    actor: Actor,
    *,
    target_id: str,
    target_type: str,
    reason: str = "spam",
    description: str = "IM400 controlled report validation",
    chat_id: str | None = None,
    expected_code: int = 0,
) -> dict[str, Any]:
    payload = {
        "target_id": target_id,
        "target_type": target_type,
        "reason": reason,
        "description": description,
    }
    if chat_id is not None:
        payload["chat_id"] = chat_id
    try:
        result = api.request("POST", "/report", actor=actor, body=payload)
    except ApiError as error:
        actual_code = int(error.payload.get("code", error.status))
        if actual_code != expected_code:
            raise
        return error.payload
    if expected_code != 0:
        raise AssertionError(f"report unexpectedly succeeded, expected code {expected_code}")
    return result


def run(base_url: str, output_dir: Path) -> dict[str, Any]:
    api = Api(base_url.rstrip("/") + "/api/v1")
    run_id = f"{int(time.time())}-{uuid.uuid4().hex[:6]}"
    a, b, c = [create_actor(api, label, run_id) for label in ("A", "B", "C")]
    private_ab = create_chat(api, a, 1, [b])
    group_ab = create_chat(api, a, 2, [b], f"REPORT_GROUP_{run_id}"[:32])

    user_report = response_data(report(api, a, target_id=b.user_id, target_type="user"))
    assert isinstance(user_report, dict) and user_report.get("id"), user_report
    report(api, a, target_id=b.user_id, target_type="user", expected_code=400)
    report(api, a, target_id=a.user_id, target_type="user", expected_code=400)
    report(api, a, target_id=str(uuid.uuid4()), target_type="user", expected_code=404)
    report(api, a, target_id="x" * 64, target_type="user", expected_code=400)

    group_report = response_data(report(api, b, target_id=group_ab, target_type="group", reason="harassment"))
    assert isinstance(group_report, dict) and group_report.get("id"), group_report
    report(api, c, target_id=group_ab, target_type="group", expected_code=403)
    report(api, b, target_id=group_ab, target_type="channel", expected_code=400)

    incoming = send_text(api, b, private_ab, f"REPORT_MESSAGE_{run_id}")
    outgoing = send_text(api, a, private_ab, f"SELF_REPORT_MESSAGE_{run_id}")
    message_report = response_data(
        report(
            api,
            a,
            target_id=str(incoming["msg_id"]),
            target_type="message",
            chat_id=private_ab,
            reason="spam",
        )
    )
    assert isinstance(message_report, dict) and message_report.get("id"), message_report
    report(
        api,
        a,
        target_id=str(incoming["msg_id"]),
        target_type="message",
        chat_id=private_ab,
        expected_code=400,
    )
    report(
        api,
        a,
        target_id=str(outgoing["msg_id"]),
        target_type="message",
        chat_id=private_ab,
        expected_code=400,
    )
    report(
        api,
        c,
        target_id=str(incoming["msg_id"]),
        target_type="message",
        chat_id=private_ab,
        expected_code=403,
    )
    report(
        api,
        a,
        target_id=str(incoming["msg_id"]),
        target_type="message",
        expected_code=400,
    )
    report(
        api,
        a,
        target_id=str(incoming["msg_id"]),
        target_type="message",
        chat_id=group_ab,
        expected_code=404,
    )

    report(api, b, target_id=a.user_id, target_type="user", reason="false_info", expected_code=400)
    report(
        api,
        b,
        target_id=a.user_id,
        target_type="user",
        reason="other",
        description="界" * 501,
        expected_code=400,
    )

    result = {
        "case_ids": ["IM-392"],
        "status": "PASS",
        "detail": (
            "user, group and message reports persisted; duplicate, self, missing target, "
            "type mismatch, non-member, invalid reason and overlong details were rejected"
        ),
    }
    report_data = {
        "run_id": run_id,
        "base_url": base_url,
        "actors": [{"name": actor.name, "user_id": actor.user_id} for actor in (a, b, c)],
        "chat_ids": {"private": private_ab, "group": group_ab},
        "results": [result],
        "summary": {"passed_assertion_groups": 1, "covered_case_ids": ["IM-392"]},
    }
    output_dir.mkdir(parents=True, exist_ok=True)
    report_path = output_dir / f"report-api-{run_id}.json"
    report_path.write_text(json.dumps(report_data, ensure_ascii=False, indent=2), encoding="utf-8")
    report_data["report_path"] = str(report_path)
    return report_data


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", default="http://127.0.0.1:8080")
    parser.add_argument("--output-dir", required=True)
    args = parser.parse_args()
    try:
        result = run(args.base_url, Path(args.output_dir).resolve())
    except Exception as error:  # noqa: BLE001
        print(json.dumps({"status": "FAIL", "error": str(error)}, ensure_ascii=False, indent=2))
        return 1
    print(json.dumps({"status": "PASS", **result}, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
