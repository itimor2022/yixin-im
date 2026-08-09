#!/usr/bin/env python3
"""Validate the complete friend-request state machine against local Docker."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
import uuid
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Any, Callable

from run_im400_device_unblocked_api import create_account
from run_im400_remaining_api import Api, check, create_chat, get_messages, list_items, response_data, send_text


def contacts(api: Api, actor: Any) -> list[dict[str, Any]]:
    return list_items(api.request("GET", "/contact/list?page=1&page_size=100", actor=actor))


def requests(api: Api, actor: Any, box: str) -> list[dict[str, Any]]:
    return list_items(api.request("GET", f"/contact/requests?box={box}", actor=actor))


def send_request(api: Api, actor: Any, target_id: str, message: str, source_ip: str) -> dict[str, Any]:
    data = response_data(
        api.request(
            "POST",
            "/contact/requests",
            actor=actor,
            extra_headers={"X-Forwarded-For": source_ip},
            body={"user_id": target_id, "message": message},
        )
    )
    check(isinstance(data, dict) and isinstance(data.get("request"), dict), f"request payload is invalid: {data}")
    return data


def expire_request_in_local_mysql(request_id: str) -> None:
    sql = (
        "UPDATE friend_requests "
        "SET expires_at = DATE_SUB(NOW(3), INTERVAL 1 SECOND) "
        f"WHERE uuid = '{request_id}';"
    )
    subprocess.run(
        [
            "docker",
            "exec",
            "genericim-mysql",
            "mysql",
            "-ugenericim",
            "-pgenericim",
            "genericim",
            "-e",
            sql,
        ],
        check=True,
        capture_output=True,
        text=True,
    )


def run(base_url: str, output_dir: Path) -> dict[str, Any]:
    api = Api(base_url.rstrip("/") + "/api/v1")
    run_id = f"{int(time.time())}-{uuid.uuid4().hex[:6]}"
    results: list[dict[str, Any]] = []

    def record(case_ids: list[str], body: Callable[[], str]) -> None:
        try:
            results.append({"case_ids": case_ids, "status": "PASS", "detail": body()})
        except Exception as exc:  # noqa: BLE001 - preserve independent evidence
            results.append(
                {
                    "case_ids": case_ids,
                    "status": "FAIL",
                    "detail": f"{type(exc).__name__}: {exc}",
                }
            )

    account_a = create_account(api, "FriendA", run_id)
    account_b = create_account(api, "FriendB", run_id)
    a = account_a.sessions["android"]
    b = account_b.sessions["android"]
    first_request: dict[str, Any] = {}

    def send_and_deduplicate() -> str:
        first = send_request(api, a, b.user_id, f"VERIFY_{run_id}", "198.51.100.61")
        duplicate = send_request(api, a, b.user_id, f"VERIFY_DUP_{run_id}", "198.51.100.61")
        first_request.update(first["request"])
        check(first.get("created") is True, f"first request was not created: {first}")
        check(duplicate.get("created") is False, f"duplicate request created another row: {duplicate}")
        check(first["request"]["id"] == duplicate["request"]["id"], "duplicate request id changed")
        incoming = requests(api, b, "incoming")
        outgoing = requests(api, a, "outgoing")
        check(sum(item.get("id") == first_request["id"] for item in incoming) == 1, f"recipient request list is wrong: {incoming}")
        check(sum(item.get("id") == first_request["id"] for item in outgoing) == 1, f"sender request list is wrong: {outgoing}")
        check(
            not any(item.get("uuid") == b.user_id for item in contacts(api, a))
            and not any(item.get("uuid") == a.user_id for item in contacts(api, b)),
            "pending request created the target contact prematurely",
        )
        check(first_request.get("message") == f"VERIFY_{run_id}", "verification message was not preserved")
        return "the verification message appeared in incoming/outgoing state, while a duplicate submission returned the same pending request without creating contacts or extra rows"

    record(["IM-064", "IM-065"], send_and_deduplicate)

    def accept_request() -> str:
        check(first_request.get("id"), "request setup did not complete")
        accepted = response_data(
            api.request(
                "POST",
                f"/contact/requests/{first_request['id']}/accept",
                actor=b,
            )
        )
        check(isinstance(accepted, dict) and accepted.get("status") == "accepted", f"accept response is wrong: {accepted}")
        check(any(item.get("uuid") == b.user_id for item in contacts(api, a)), "sender contact list did not add recipient")
        check(any(item.get("uuid") == a.user_id for item in contacts(api, b)), "recipient contact list did not add sender")
        chat_id = create_chat(api, a, 1, [b])
        message = send_text(api, a, chat_id, f"FRIEND_CHAT_{run_id}")
        check(any(item.get("msg_id") == message["msg_id"] for item in get_messages(api, b, chat_id)), "accepted friends could not chat immediately")
        return "accepting the request atomically created both contact rows and the users could immediately create a private chat and exchange a message"

    record(["IM-066"], accept_request)

    def reject_request() -> str:
        c_account = create_account(api, "RejectC", run_id)
        d_account = create_account(api, "RejectD", run_id)
        c = c_account.sessions["android"]
        d = d_account.sessions["android"]
        sent = send_request(api, c, d.user_id, f"REJECT_{run_id}", "198.51.100.62")
        rejected = response_data(
            api.request(
                "POST",
                f"/contact/requests/{sent['request']['id']}/reject",
                actor=d,
            )
        )
        check(isinstance(rejected, dict) and rejected.get("status") == "rejected", f"reject response is wrong: {rejected}")
        check(
            not any(item.get("uuid") == d.user_id for item in contacts(api, c))
            and not any(item.get("uuid") == c.user_id for item in contacts(api, d)),
            "rejected request created the target contact relation",
        )
        outgoing = next(item for item in requests(api, c, "outgoing") if item.get("id") == sent["request"]["id"])
        check(outgoing.get("status") == "rejected", f"sender did not receive privacy-safe terminal state: {outgoing}")
        return "the recipient rejected the request, no contact rows were created, and the sender only received the terminal rejected state"

    record(["IM-067"], reject_request)

    def expire_and_resend() -> str:
        e_account = create_account(api, "ExpireE", run_id)
        f_account = create_account(api, "ExpireF", run_id)
        e = e_account.sessions["android"]
        f = f_account.sessions["android"]
        sent = send_request(api, e, f.user_id, f"EXPIRE_{run_id}", "198.51.100.63")
        request_id = str(sent["request"]["id"])
        expire_request_in_local_mysql(request_id)
        payload = api.request(
            "POST",
            f"/contact/requests/{request_id}/accept",
            actor=f,
            expected_status=400,
        )
        check("过期" in str(payload.get("message", "")), f"expired response is unclear: {payload}")
        expired = next(item for item in requests(api, f, "incoming") if item.get("id") == request_id)
        check(expired.get("status") == "expired", f"expired state did not persist: {expired}")
        resent = send_request(api, e, f.user_id, f"RESEND_{run_id}", "198.51.100.63")
        check(resent.get("created") is True and resent["request"]["id"] != request_id, f"expired request could not be resent: {resent}")
        return "an expired request was rejected with a clear error and persisted as expired; the sender could create a new pending request afterward"

    record(["IM-068"], expire_and_resend)

    def simultaneous_requests() -> str:
        g_account = create_account(api, "CrossG", run_id)
        h_account = create_account(api, "CrossH", run_id)
        g = g_account.sessions["android"]
        h = h_account.sessions["android"]
        with ThreadPoolExecutor(max_workers=2) as pool:
            future_g = pool.submit(send_request, api, g, h.user_id, f"CROSS_G_{run_id}", "198.51.100.64")
            future_h = pool.submit(send_request, api, h, g.user_id, f"CROSS_H_{run_id}", "198.51.100.65")
            responses = [future_g.result(), future_h.result()]
        check(sum(item.get("auto_accepted") is True for item in responses) == 1, f"cross requests did not merge once: {responses}")
        check(any(item.get("uuid") == h.user_id for item in contacts(api, g)), "G did not receive H as a contact")
        check(any(item.get("uuid") == g.user_id for item in contacts(api, h)), "H did not receive G as a contact")
        all_ids = {
            item.get("id")
            for item in requests(api, g, "outgoing") + requests(api, g, "incoming")
            if item.get("user", {}).get("uuid") == h.user_id
        }
        check(len(all_ids) == 1, f"cross requests created conflicting rows: {all_ids}")
        statuses = {
            item.get("status")
            for item in requests(api, g, "outgoing") + requests(api, g, "incoming")
            if item.get("id") in all_ids
        }
        check(statuses == {"accepted"}, f"cross request status is inconsistent: {statuses}")
        return "two concurrent opposite requests serialized on the user pair, auto-accepted exactly once, created mutual contacts, and retained one accepted request row"

    record(["IM-069"], simultaneous_requests)

    report = {
        "run_id": run_id,
        "base_url": base_url,
        "results": results,
        "summary": {
            "pass": sum(result["status"] == "PASS" for result in results),
            "fail": sum(result["status"] == "FAIL" for result in results),
            "covered_case_ids": sorted({case_id for result in results for case_id in result["case_ids"]}),
        },
    }
    output_dir.mkdir(parents=True, exist_ok=True)
    report_path = output_dir / f"friend-request-api-{run_id}.json"
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
