#!/usr/bin/env python3
"""Batch K current-source API regression for call time and push settings."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import sys
import time
import uuid
from pathlib import Path
from typing import Any

from run_im400_remaining_api import (
    Actor,
    Api,
    check,
    create_actor,
    response_data,
)


def data_object(payload: dict[str, Any], context: str) -> dict[str, Any]:
    data = response_data(payload)
    check(isinstance(data, dict), f"{context} response data is invalid: {payload}")
    return data


def parse_time(value: Any, context: str) -> dt.datetime:
    check(value is not None, f"{context} time is missing")
    parsed = dt.datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=dt.timezone.utc)
    return parsed.astimezone(dt.timezone.utc)


def push_settings(api: Api, actor: Actor) -> dict[str, Any]:
    return data_object(api.request("GET", "/user/push-settings", actor=actor), "push settings")


def active_call(api: Api, actor: Actor) -> dict[str, Any]:
    return data_object(api.request("GET", "/call/active", actor=actor), "active call")


def run(base_url: str, output_dir: Path) -> dict[str, Any]:
    api = Api(base_url.rstrip("/") + "/api/v1")
    run_id = f"{int(time.time())}-{uuid.uuid4().hex[:6]}"
    a, b, c = [create_actor(api, label, run_id) for label in ("A", "B", "C")]
    results: list[dict[str, Any]] = []

    def passed(case_ids: list[str], detail: str) -> None:
        results.append({"case_ids": case_ids, "status": "PASS", "detail": detail})

    initial_a = push_settings(api, a)
    initial_b = push_settings(api, b)
    check(
        initial_a == {"enabled": True, "show_preview": True}
        and initial_b == {"enabled": True, "show_preview": True},
        f"unexpected default push settings: A={initial_a}, B={initial_b}",
    )
    api.request(
        "PUT",
        "/user/push-settings",
        actor=a,
        body={"enabled": False, "show_preview": False},
    )
    disabled_a = push_settings(api, a)
    check(
        disabled_a == {"enabled": False, "show_preview": False},
        f"master/preview disable did not persist: {disabled_a}",
    )
    check(
        push_settings(api, b) == initial_b,
        "A push settings leaked into B account",
    )
    api.request(
        "PUT",
        "/user/push-settings",
        actor=a,
        body={"show_preview": True},
    )
    partial_a = push_settings(api, a)
    check(
        partial_a == {"enabled": False, "show_preview": True},
        f"partial preview update reset the master switch: {partial_a}",
    )
    passed(
        ["IM-346", "IM-349"],
        "server persisted privacy/master switches independently and isolated them by account",
    )

    created = data_object(
        api.request(
            "POST",
            "/call/create",
            actor=a,
            body={"target_user_id": b.user_id, "call_type": "video"},
        ),
        "call create",
    )
    call_id = int(created.get("call_id", 0))
    check(call_id > 0, f"call id is invalid: {created}")

    api.request(
        "POST",
        "/call/accept",
        actor=c,
        body={"call_id": call_id},
        expected_status=403,
    )
    accepted = data_object(
        api.request(
            "POST",
            "/call/accept",
            actor=b,
            body={"call_id": call_id},
        ),
        "call accept",
    )
    accepted_at = parse_time(accepted.get("connected_at"), "accept")

    active_a = active_call(api, a)
    active_b = active_call(api, b)
    check(
        active_a.get("active") is True
        and active_b.get("active") is True
        and int(active_a.get("call_id", 0)) == call_id
        and int(active_b.get("call_id", 0)) == call_id,
        f"participants do not share one active call: A={active_a}, B={active_b}",
    )
    active_a_time = parse_time(active_a.get("connect_time"), "caller active")
    active_b_time = parse_time(active_b.get("connect_time"), "callee active")
    check(
        abs((active_a_time - accepted_at).total_seconds()) < 0.01
        and active_a_time == active_b_time,
        f"connected time diverged: accept={accepted_at}, A={active_a_time}, B={active_b_time}",
    )

    api.request(
        "POST",
        "/call/heartbeat",
        actor=c,
        body={"call_id": call_id},
        expected_status=403,
    )
    time.sleep(1.2)
    for actor in (a, b):
        heartbeat = data_object(
            api.request(
                "POST",
                "/call/heartbeat",
                actor=actor,
                body={"call_id": call_id},
            ),
            f"{actor.name} heartbeat",
        )
        check(
            heartbeat.get("active") is True and heartbeat.get("status") == "connected",
            f"{actor.name} heartbeat lost the connected state: {heartbeat}",
        )
    time.sleep(1.2)
    media = data_object(
        api.request(
            "POST",
            "/call/media-state",
            actor=a,
            body={"call_id": call_id, "video_enabled": False},
        ),
        "media state",
    )
    check(
        media.get("call_type") == "video" and media.get("video_enabled") is False,
        f"camera-off changed the call identity/type: {media}",
    )

    active_after_heartbeat = active_call(api, b)
    stable_time = parse_time(active_after_heartbeat.get("connect_time"), "active after heartbeat")
    check(
        stable_time == active_a_time,
        f"heartbeat/media update reset authoritative connected time: {stable_time} != {active_a_time}",
    )
    passed(
        ["IM-313", "IM-314", "IM-315", "IM-323"],
        "both participants retained one server connected_at across heartbeats and media-state refreshes",
    )

    ended = data_object(
        api.request(
            "POST",
            "/call/end",
            actor=b,
            body={"call_id": call_id, "reason": "hangup"},
        ),
        "call end",
    )
    duration = int(ended.get("duration", -1))
    check(
        ended.get("released") is True
        and ended.get("status") == "ended"
        and duration >= 2,
        f"ended call did not preserve elapsed duration/release state: {ended}",
    )
    ended_retry = data_object(
        api.request(
            "POST",
            "/call/end",
            actor=a,
            body={"call_id": call_id, "reason": "hangup"},
        ),
        "call end retry",
    )
    check(
        int(ended_retry.get("duration", -1)) == duration
        and ended_retry.get("status") == "ended",
        f"idempotent end changed duration/state: first={ended}, retry={ended_retry}",
    )

    report = {
        "run_id": run_id,
        "base_url": base_url,
        "actors": [{"name": actor.name, "user_id": actor.user_id} for actor in (a, b, c)],
        "call_id": call_id,
        "connected_at": accepted_at.isoformat(),
        "duration_seconds": duration,
        "results": results,
        "summary": {
            "passed_assertion_groups": len(results),
            "covered_case_ids": sorted(
                {case_id for result in results for case_id in result["case_ids"]}
            ),
        },
    }
    output_dir.mkdir(parents=True, exist_ok=True)
    report_path = output_dir / f"call-notification-api-{run_id}.json"
    report_path.write_text(
        json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8"
    )
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
