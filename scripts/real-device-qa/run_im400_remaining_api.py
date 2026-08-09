#!/usr/bin/env python3
"""Exercise remaining IM-400 message and group contracts against a local API.

The runner creates isolated local test accounts and never persists
access tokens. It is intended for a current-source local backend, not production.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Any


@dataclass
class Actor:
    name: str
    user_id: str
    token: str


class ApiError(RuntimeError):
    def __init__(self, method: str, path: str, status: int, payload: Any):
        super().__init__(f"{method} {path} returned HTTP {status}: {payload}")
        self.method = method
        self.path = path
        self.status = status
        self.payload = payload


class Api:
    def __init__(self, base_url: str):
        self.base_url = base_url.rstrip("/")

    def request(
        self,
        method: str,
        path: str,
        *,
        actor: Actor | None = None,
        body: dict[str, Any] | None = None,
        expected_status: int = 200,
        extra_headers: dict[str, str] | None = None,
    ) -> dict[str, Any]:
        data = None if body is None else json.dumps(body).encode("utf-8")
        headers = {"Accept": "application/json"}
        if body is not None:
            headers["Content-Type"] = "application/json"
        if actor is not None:
            headers["Authorization"] = f"Bearer {actor.token}"
        if extra_headers:
            headers.update(extra_headers)
        request = urllib.request.Request(
            f"{self.base_url}{path}", data=data, headers=headers, method=method
        )
        try:
            with urllib.request.urlopen(request, timeout=20) as response:
                status = response.status
                raw = response.read().decode("utf-8")
        except urllib.error.HTTPError as error:
            status = error.code
            raw = error.read().decode("utf-8", errors="replace")
        payload: dict[str, Any]
        try:
            payload = json.loads(raw) if raw else {}
        except json.JSONDecodeError:
            payload = {"raw": raw}
        if status != expected_status:
            raise ApiError(method, path, status, payload)
        if expected_status < 400 and payload.get("code") != 0:
            raise ApiError(method, path, status, payload)
        return payload


def response_data(payload: dict[str, Any]) -> Any:
    return payload.get("data")


def list_items(payload: dict[str, Any]) -> list[dict[str, Any]]:
    data = response_data(payload)
    if isinstance(data, list):
        return data
    if isinstance(data, dict):
        for key in ("items", "list", "messages", "rows"):
            value = data.get(key)
            if isinstance(value, list):
                return value
    raise AssertionError(f"response does not contain a list: {payload}")


def check(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def create_actor(api: Api, label: str, run_id: str) -> Actor:
    username = f"qa_{label.lower()}_{run_id.replace('-', '')}"[:20]
    payload = api.request(
        "POST",
        "/auth/register",
        body={
            "username": username,
            "password": f"Qa{uuid.uuid4().hex[:12]}",
            "nickname": f"IM400 API {label}",
            "gender": "male",
            "device_id": f"im400-api-{label.lower()}-{run_id}",
            "device_type": "qa",
            "device_name": f"IM400 API {label}",
        },
    )
    data = response_data(payload)
    check(isinstance(data, dict), "quick register response data is missing")
    user = data.get("user")
    check(isinstance(user, dict), "quick register user is missing")
    return Actor(label, str(user["uuid"]), str(data["token"]))


def create_chat(api: Api, actor: Actor, chat_type: int, members: list[Actor], name: str = "") -> str:
    payload = api.request(
        "POST",
        "/chat/create",
        actor=actor,
        body={
            "type": chat_type,
            "name": name,
            "member_ids": [member.user_id for member in members],
        },
    )
    data = response_data(payload)
    check(isinstance(data, dict) and data.get("uuid"), f"chat uuid missing: {payload}")
    return str(data["uuid"])


def send_text(
    api: Api,
    actor: Actor,
    chat_id: str,
    text: str,
    *,
    mention_all: bool = False,
    expected_status: int = 200,
) -> dict[str, Any]:
    payload = api.request(
        "POST",
        "/message/send",
        actor=actor,
        expected_status=expected_status,
        body={
            "chat_id": chat_id,
            "type": 1,
            "content": {"text": text},
            "msg_id": str(uuid.uuid4()),
            "mention_all": mention_all,
        },
    )
    data = response_data(payload)
    return data if isinstance(data, dict) else payload


def get_messages(api: Api, actor: Actor, chat_id: str) -> list[dict[str, Any]]:
    query = urllib.parse.urlencode({"chat_id": chat_id, "before_seq": 0, "limit": 100})
    return list_items(api.request("GET", f"/message/list?{query}", actor=actor))


def run(base_url: str, output_dir: Path) -> dict[str, Any]:
    api = Api(base_url.rstrip("/") + "/api/v1")
    run_id = f"{int(time.time())}-{uuid.uuid4().hex[:6]}"
    actors = [create_actor(api, label, run_id) for label in ("A", "B", "C")]
    a, b, c = actors
    results: list[dict[str, Any]] = []

    def passed(case_ids: list[str], detail: str) -> None:
        results.append({"case_ids": case_ids, "status": "PASS", "detail": detail})

    chat_ab = create_chat(api, a, 1, [b])
    chat_ac = create_chat(api, a, 1, [c])
    source_one = send_text(api, a, chat_ab, f"SOURCE_ONE_{run_id}")
    source_two = send_text(api, a, chat_ab, f"SOURCE_TWO_{run_id}")
    source_one_id = str(source_one["msg_id"])
    source_two_id = str(source_two["msg_id"])

    forward_ids = [str(uuid.uuid4()), str(uuid.uuid4())]
    forward_responses: list[dict[str, Any]] = []
    for source_id, client_id in zip((source_one_id, source_two_id), forward_ids):
        forward_responses.append(
            response_data(
                api.request(
                    "POST",
                    "/message/forward",
                    actor=a,
                    body={
                        "source_chat_id": chat_ab,
                        "source_msg_id": source_id,
                        "target_chat_id": chat_ac,
                        "client_msg_id": client_id,
                    },
                )
            )
        )
    check(all(isinstance(item, dict) for item in forward_responses), "forward response is invalid")
    forward_seqs = [int(item.get("seq", 0)) for item in forward_responses]
    check(forward_seqs == sorted(forward_seqs) and len(set(forward_seqs)) == 2, f"forward writes were not sequenced: {forward_seqs}")
    retry = response_data(
        api.request(
            "POST",
            "/message/forward",
            actor=a,
            body={
                "source_chat_id": chat_ab,
                "source_msg_id": source_one_id,
                "target_chat_id": chat_ac,
                "client_msg_id": forward_ids[0],
            },
        )
    )
    check(isinstance(retry, dict), "forward retry response is invalid")
    check(retry.get("msg_id") == forward_responses[0].get("msg_id"), "forward retry did not return the original message")
    forwarded = get_messages(api, c, chat_ac)
    forwarded_ids = [str(item.get("msg_id")) for item in forwarded]
    check(len(forwarded_ids) == len(set(forwarded_ids)), "forward retry created a duplicate message")
    history_seqs = [int(item.get("seq", 0)) for item in forwarded if item.get("sender_id") == a.user_id]
    check(len(history_seqs) == 2, f"expected two forwarded messages, got {history_seqs}")
    check(set(history_seqs) == set(forward_seqs), f"history did not preserve forward seq values: writes={forward_seqs}, history={history_seqs}")
    passed(["IM-215", "IM-216"], "two forwards received increasing server sequences; descending history pagination preserved both and stable client id retry returned the original message without duplication")

    favorite = response_data(
        api.request(
            "POST",
            "/message/favorite",
            actor=a,
            body={"chat_id": chat_ab, "message_id": source_one_id},
        )
    )
    check(isinstance(favorite, dict) and favorite.get("message_id") == source_one_id, "favorite snapshot is invalid")
    check(len(list_items(api.request("GET", "/message/favorites?page=1&page_size=50", actor=a))) == 1, "favorite list did not contain the item")
    api.request("DELETE", f"/message/favorite/{chat_ab}/{source_one_id}", actor=a)
    check(len(list_items(api.request("GET", "/message/favorites?page=1&page_size=50", actor=a))) == 0, "favorite remained visible after delete")
    sync_items = list_items(api.request("GET", "/message/favorites/sync?since=1970-01-01T00%3A00%3A00Z", actor=a))
    tombstones = [item for item in sync_items if item.get("message_id") == source_one_id and item.get("deleted") is True]
    check(len(tombstones) == 1, "favorite sync did not return one tombstone")
    check(any(item.get("msg_id") == source_one_id for item in get_messages(api, a, chat_ab)), "deleting favorite removed the source message")
    passed(["IM-219"], "favorite deletion returned one sync tombstone and preserved the original chat message")

    detail_query = urllib.parse.urlencode({"chat_id": chat_ab, "msg_id": source_one_id})
    detail = response_data(api.request("GET", f"/message/detail?{detail_query}", actor=a))
    check(isinstance(detail, dict) and detail.get("message", {}).get("message_id") == source_one_id, "authoritative detail payload is invalid")
    api.request("GET", f"/message/detail?{detail_query}", actor=c, expected_status=403)
    passed(["IM-220"], "chat member received authoritative detail; non-member was rejected with HTTP 403")

    api.request("POST", f"/chat/{chat_ab}/clear-both", actor=a, body={})
    check(len(get_messages(api, a, chat_ab)) == 0, "sender still sees messages after clear-both")
    check(len(get_messages(api, b, chat_ab)) == 0, "recipient still sees messages after clear-both")
    check(len(get_messages(api, c, chat_ac)) == 2, "clear-both affected another conversation")
    passed(["IM-210"], "both participants lost the cleared history while the separate target conversation remained intact")

    group_id = create_chat(api, a, 2, [b, c], f"IM400_API_{run_id}"[:32])
    send_text(api, b, group_id, f"DENIED_{run_id}", mention_all=True, expected_status=403)
    api.request("PUT", f"/chat/{group_id}/members/{b.user_id}/role", actor=a, body={"role": 1})
    admin_message = send_text(api, b, group_id, f"ADMIN_ALLOWED_{run_id}", mention_all=True)
    check("__all__" in (admin_message.get("mentions") or []), "admin mention-all sentinel was not persisted")
    api.request("PUT", f"/chat/{group_id}/members/{b.user_id}/role", actor=a, body={"role": 0})
    send_text(api, b, group_id, f"REVOKED_{run_id}", mention_all=True, expected_status=403)
    passed(["IM-270", "IM-271", "IM-286"], "member mention-all was denied, allowed immediately as admin, and denied again after role revocation")

    existing_group_message = send_text(api, b, group_id, f"BEFORE_DISSOLVE_{run_id}")
    api.request("DELETE", f"/chat/{group_id}", actor=a)
    dissolved = response_data(api.request("GET", f"/chat/{group_id}", actor=b))
    check(isinstance(dissolved, dict) and dissolved.get("status") == 2, "member did not receive the dissolved terminal state")
    dissolved_history = get_messages(api, b, group_id)
    check(any(item.get("msg_id") == existing_group_message.get("msg_id") for item in dissolved_history), "dissolved group history was not retained")
    send_text(api, b, group_id, f"AFTER_DISSOLVE_{run_id}", expected_status=403)
    api.request(
        "PUT",
        f"/chat/{group_id}/members/{b.user_id}/role",
        actor=a,
        body={"role": 1},
        expected_status=403,
    )
    passed(["IM-259", "IM-260"], "dissolve kept the terminal state and readable history while rejecting new messages and stale role mutations")

    first_call = response_data(
        api.request(
            "POST",
            "/call/create",
            actor=a,
            body={"target_user_id": b.user_id, "call_type": "video"},
        )
    )
    check(isinstance(first_call, dict) and first_call.get("call_id"), "initial call response is invalid")
    call_id = int(first_call["call_id"])
    expires_at = dt.datetime.fromisoformat(str(first_call["expires_at"]).replace("Z", "+00:00"))
    remaining_seconds = (expires_at - dt.datetime.now(dt.timezone.utc)).total_seconds()
    check(25 <= remaining_seconds <= 31, f"ring timeout is not approximately 30 seconds: {remaining_seconds}")

    reverse_call = response_data(
        api.request(
            "POST",
            "/call/create",
            actor=b,
            body={"target_user_id": a.user_id, "call_type": "video"},
        )
    )
    check(isinstance(reverse_call, dict), "reverse call response is invalid")
    check(int(reverse_call.get("call_id", 0)) == call_id and reverse_call.get("arbitrated") is True, "reverse simultaneous call did not reuse the original call id")
    for actor in (a, b):
        active_call = response_data(api.request("GET", "/call/active", actor=actor))
        check(isinstance(active_call, dict) and active_call.get("active") is True, f"{actor.name} does not see the active call")
        check(int(active_call.get("call_id", 0)) == call_id and active_call.get("status") == "connected", f"{actor.name} active call state is inconsistent")
    passed(["IM-305", "IM-318"], "ring expiry was approximately 30 seconds and the reverse simultaneous call reused one connected call id")

    api.request(
        "POST",
        "/call/media-state",
        actor=c,
        body={"call_id": call_id, "video_enabled": False},
        expected_status=403,
    )
    camera_off = response_data(
        api.request(
            "POST",
            "/call/media-state",
            actor=a,
            body={"call_id": call_id, "video_enabled": False},
        )
    )
    check(isinstance(camera_off, dict) and camera_off.get("call_type") == "video" and camera_off.get("video_enabled") is False, "camera-off state is inconsistent")
    voice_only = response_data(
        api.request(
            "POST",
            "/call/media-state",
            actor=b,
            body={"call_id": call_id, "call_type": "voice"},
        )
    )
    check(isinstance(voice_only, dict) and voice_only.get("call_type") == "voice" and voice_only.get("video_enabled") is False, "video-to-voice downgrade failed")
    api.request(
        "POST",
        "/call/media-state",
        actor=a,
        body={"call_id": call_id, "call_type": "video"},
        expected_status=400,
    )
    passed(["IM-308", "IM-337"], "non-participant media mutation was denied; camera-off and one-way voice downgrade persisted; voice-to-video upgrade was rejected")

    ended = response_data(api.request("POST", "/call/end", actor=a, body={"call_id": call_id, "reason": "hangup"}))
    check(isinstance(ended, dict) and ended.get("released") is True and ended.get("status") == "ended", "call did not release cleanly")
    ended_again = response_data(api.request("POST", "/call/end", actor=b, body={"call_id": call_id, "reason": "hangup"}))
    check(isinstance(ended_again, dict) and ended_again.get("released") is True and ended_again.get("status") == "ended", "idempotent call end failed")
    active_after_end = response_data(api.request("GET", "/call/active", actor=b))
    check(isinstance(active_after_end, dict) and active_after_end.get("active") is False, "ended call still occupies the callee")
    passed(["IM-324"], "call end was idempotent and released the active-call slot for both participants")

    report = {
        "run_id": run_id,
        "base_url": base_url,
        "actors": [{"name": actor.name, "user_id": actor.user_id} for actor in actors],
        "chat_ids": {"private_ab": chat_ab, "private_ac": chat_ac, "group": group_id},
        "results": results,
        "summary": {
            "passed_assertion_groups": len(results),
            "covered_case_ids": sorted({case_id for result in results for case_id in result["case_ids"]}),
        },
    }
    output_dir.mkdir(parents=True, exist_ok=True)
    report_path = output_dir / f"remaining-api-{run_id}.json"
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
    except Exception as error:  # noqa: BLE001 - QA runner must print one actionable failure
        print(json.dumps({"status": "FAIL", "error": str(error)}, ensure_ascii=False, indent=2))
        return 1
    print(json.dumps({"status": "PASS", **report}, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
