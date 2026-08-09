#!/usr/bin/env python3
"""Stress IM-318 with genuinely concurrent reverse call-create requests."""

from __future__ import annotations

import argparse
import json
import sys
import threading
import time
import uuid
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Any

from run_im400_remaining_api import Actor, Api, check, create_actor, response_data


def data_object(payload: dict[str, Any], context: str) -> dict[str, Any]:
    data = response_data(payload)
    check(isinstance(data, dict), f"{context} response data is invalid: {payload}")
    return data


def create_call_at_barrier(
    api: Api,
    actor: Actor,
    target: Actor,
    barrier: threading.Barrier,
) -> dict[str, Any]:
    barrier.wait(timeout=10)
    return data_object(
        api.request(
            "POST",
            "/call/create",
            actor=actor,
            body={"target_user_id": target.user_id, "call_type": "voice"},
        ),
        f"{actor.name}->{target.name} call create",
    )


def run(base_url: str, output_dir: Path, iterations: int) -> dict[str, Any]:
    check(iterations > 0, "iterations must be positive")
    api = Api(base_url.rstrip("/") + "/api/v1")
    run_id = f"{int(time.time())}-{uuid.uuid4().hex[:6]}"
    actor_a = create_actor(api, "A", run_id)
    actor_b = create_actor(api, "B", run_id)
    rounds: list[dict[str, Any]] = []
    observed_call_ids: set[int] = set()
    observed_channels: set[str] = set()

    for index in range(1, iterations + 1):
        barrier = threading.Barrier(3)
        with ThreadPoolExecutor(max_workers=2) as executor:
            future_a = executor.submit(
                create_call_at_barrier,
                api,
                actor_a,
                actor_b,
                barrier,
            )
            future_b = executor.submit(
                create_call_at_barrier,
                api,
                actor_b,
                actor_a,
                barrier,
            )
            barrier.wait(timeout=10)
            result_a = future_a.result(timeout=30)
            result_b = future_b.result(timeout=30)

        call_id_a = int(result_a.get("call_id", 0))
        call_id_b = int(result_b.get("call_id", 0))
        check(call_id_a > 0 and call_id_b > 0, f"round {index} missing call id: A={result_a}, B={result_b}")
        check(call_id_a == call_id_b, f"round {index} split into two calls: A={result_a}, B={result_b}")
        check(
            result_a.get("channel_name") == result_b.get("channel_name"),
            f"round {index} split RTC channels: A={result_a}, B={result_b}",
        )
        channel_name = str(result_a.get("channel_name", "")).strip()
        check(channel_name, f"round {index} channel is empty: A={result_a}, B={result_b}")
        check(
            channel_name not in observed_channels,
            f"round {index} reused an earlier RTC channel: {channel_name}",
        )
        arbitrated_count = sum(
            value.get("arbitrated") is True for value in (result_a, result_b)
        )
        check(arbitrated_count == 1, f"round {index} arbitration count={arbitrated_count}: A={result_a}, B={result_b}")

        active_a = data_object(api.request("GET", "/call/active", actor=actor_a), "A active call")
        active_b = data_object(api.request("GET", "/call/active", actor=actor_b), "B active call")
        for actor_name, active in (("A", active_a), ("B", active_b)):
            check(active.get("active") is True, f"round {index} {actor_name} has no active call: {active}")
            check(int(active.get("call_id", 0)) == call_id_a, f"round {index} {actor_name} sees another call: {active}")
            check(active.get("status") == "connected", f"round {index} {actor_name} state is not connected: {active}")

        ended = data_object(
            api.request(
                "POST",
                "/call/end",
                actor=actor_a,
                body={"call_id": call_id_a, "reason": "qa_iteration_cleanup"},
            ),
            "call end",
        )
        check(ended.get("released") is True, f"round {index} did not release call: {ended}")
        observed_call_ids.add(call_id_a)
        observed_channels.add(channel_name)
        rounds.append(
            {
                "round": index,
                "call_id": call_id_a,
                "channel_name": channel_name,
                "arbitrated_side": "A" if result_a.get("arbitrated") is True else "B",
                "status": "PASS",
            }
        )

    check(
        len(observed_call_ids) == iterations,
        f"call ids were unexpectedly reused across rounds: {sorted(observed_call_ids)}",
    )
    for actor in (actor_a, actor_b):
        active = data_object(api.request("GET", "/call/active", actor=actor), "final active call")
        check(active.get("active") is False, f"{actor.name} retained an active call after cleanup: {active}")

    report = {
        "case_id": "IM-318",
        "status": "PASS_CURRENT_SOURCE_CONCURRENCY",
        "run_id": run_id,
        "base_url": base_url,
        "iterations": iterations,
        "unique_call_ids": len(observed_call_ids),
        "unique_channels": len(observed_channels),
        "split_call_count": 0,
        "residual_active_call_count": 0,
        "rounds": rounds,
        "note": "Each round released two HTTP requests through one barrier and required one shared connected call_id/channel with exactly one arbitrated response.",
    }
    output_dir.mkdir(parents=True, exist_ok=True)
    path = output_dir / f"im318-simultaneous-call-{run_id}.json"
    path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    report["report_path"] = str(path)
    return report


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", default="http://127.0.0.1:8080")
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--iterations", type=int, default=25)
    args = parser.parse_args()
    try:
        report = run(args.base_url, Path(args.output_dir).resolve(), args.iterations)
    except Exception as error:  # noqa: BLE001
        print(json.dumps({"status": "FAIL", "error": str(error)}, ensure_ascii=False, indent=2))
        return 1
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
