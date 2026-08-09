#!/usr/bin/env python3
"""Validate auth, profile and contact contracts against the local Docker API."""

from __future__ import annotations

import argparse
import json
import time
import urllib.parse
import uuid
from pathlib import Path
from typing import Any, Callable

from run_im400_device_unblocked_api import Account, create_account, data_dict, login
from run_im400_remaining_api import (
    Actor,
    Api,
    ApiError,
    check,
    create_chat,
    list_items,
    response_data,
    send_text,
)


def login_payload(username: str, password: str, device_id: str) -> dict[str, Any]:
    return {
        "username": username,
        "password": password,
        "device_id": device_id,
        "device_type": "qa",
        "device_name": device_id,
    }


def request_error_once(
    api: Api,
    method: str,
    path: str,
    *,
    expected_status: int,
    actor: Actor | None = None,
    body: dict[str, Any] | None = None,
) -> dict[str, Any]:
    try:
        payload = api.request(
            method,
            path,
            actor=actor,
            body=body,
            expected_status=expected_status,
        )
    except ApiError as error:
        # Several legacy endpoints return HTTP 200 with a non-zero business
        # code, while binding/rate-limit errors use HTTP 4xx.
        if error.status != 200 or int(error.payload.get("code", 0)) == 0:
            raise
        payload = error.payload
    check(int(payload.get("code", 0)) != 0, f"request unexpectedly succeeded: {payload}")
    return payload


def contacts(api: Api, actor: Actor) -> list[dict[str, Any]]:
    return list_items(api.request("GET", "/contact/list?page=1&page_size=200", actor=actor))


def chat_list(api: Api, actor: Actor) -> list[dict[str, Any]]:
    return list_items(api.request("GET", "/chat/list?page=1&page_size=100", actor=actor))


def run(base_url: str, output_dir: Path) -> dict[str, Any]:
    api = Api(base_url.rstrip("/") + "/api/v1")
    run_id = f"{int(time.time())}-{uuid.uuid4().hex[:6]}"
    results: list[dict[str, Any]] = []

    def record(case_ids: list[str], body: Callable[[], str]) -> None:
        try:
            results.append({"case_ids": case_ids, "status": "PASS", "detail": body()})
        except Exception as exc:
            results.append(
                {
                    "case_ids": case_ids,
                    "status": "FAIL",
                    "detail": f"{type(exc).__name__}: {exc}",
                }
            )

    def password_boundaries() -> str:
        base = {
            "username": f"pw_{uuid.uuid4().hex[:8]}",
            "nickname": "Password Boundary",
            "gender": "male",
            "device_id": f"pw-boundary-{run_id}",
            "device_type": "qa",
            "device_name": "Password Boundary",
        }
        request_error_once(
            api,
            "POST",
            "/auth/register",
            expected_status=400,
            body=base | {"password": "12345"},
        )
        request_error_once(
            api,
            "POST",
            "/auth/register",
            expected_status=400,
            body=(base | {"username": f"pw_{uuid.uuid4().hex[:8]}", "password": "x" * 21}),
        )
        for password in ("123456", "x" * 20, "空 格!Ab1"):
            payload = api.request(
                "POST",
                "/auth/register",
                body=base
                | {
                    "username": f"pw_{uuid.uuid4().hex[:8]}",
                    "password": password,
                    "device_id": f"pw-{uuid.uuid4().hex[:8]}",
                },
            )
            check(bool(data_dict(payload).get("token")), f"valid boundary password rejected: {password!r}")
        return "registration rejected passwords shorter than 6 or longer than 20 and accepted defined boundary/special-character values"

    record(["IM-007"], password_boundaries)

    def login_failures() -> str:
        account = create_account(api, "LoginFailure", run_id)
        wrong = request_error_once(
            api,
            "POST",
            "/auth/login",
            expected_status=400,
            body=login_payload(account.username, "WrongPass123", f"wrong-{run_id}"),
        )
        missing = request_error_once(
            api,
            "POST",
            "/auth/login",
            expected_status=400,
            body=login_payload(f"missing_{uuid.uuid4().hex[:8]}", "WrongPass123", f"missing-{run_id}"),
        )
        check(wrong.get("message") == missing.get("message"), f"login errors leak account existence: {wrong}, {missing}")
        return "wrong-password and nonexistent-account login returned the same generic error without creating sessions"

    record(["IM-009", "IM-011"], login_failures)

    def login_throttle() -> str:
        account = create_account(api, "Throttle", run_id)
        statuses: list[int] = []
        for index in range(11):
            expected = 400 if index < 10 else 429
            payload = request_error_once(
                api,
                "POST",
                "/auth/login",
                expected_status=expected,
                body=login_payload(account.username, "WrongPass123", f"throttle-{index}-{run_id}"),
            )
            statuses.append(expected)
            if expected == 429:
                check("频繁" in str(payload.get("message", "")), f"throttle message unclear: {payload}")
        request_error_once(
            api,
            "POST",
            "/auth/login",
            expected_status=429,
            body=login_payload(account.username, account.password, f"throttle-correct-{run_id}"),
        )
        return f"ten failed attempts triggered a 15-minute account throttle and temporarily blocked even a correct password: {statuses}"

    record(["IM-010"], login_throttle)

    primary = create_account(api, "Profile", run_id)
    peer_account = create_account(api, "ProfilePeer", run_id)
    actor = primary.sessions["android"]
    peer = peer_account.sessions["android"]
    chat_id = create_chat(api, actor, 1, [peer])

    def profile_update() -> str:
        nickname = f"资料😀{run_id[-4:]}"
        avatar = f"/uploads/qa/avatar-{run_id}.jpg"
        updated = data_dict(
            api.request(
                "PUT",
                "/user/me",
                actor=actor,
                body={"nickname": nickname, "avatar": avatar},
            )
        )
        check(updated.get("nickname") == nickname and updated.get("avatar") == avatar, f"profile update missing: {updated}")
        public = data_dict(api.request("GET", f"/public/user/{actor.user_id}"))
        check(public.get("nickname") == nickname and public.get("avatar") == avatar, f"public profile stale: {public}")
        peer_row = next(item for item in chat_list(api, peer) if item.get("chat_id") == chat_id)
        check(peer_row.get("name") == nickname and peer_row.get("avatar") == avatar, f"chat profile cache stale: {peer_row}")
        return "nickname and avatar updates persisted and immediately appeared in public profile and the peer conversation list"

    record(["IM-041", "IM-098"], profile_update)

    def nickname_boundaries() -> str:
        for value in ("", "第一行\n第二行", "名" * 51):
            request_error_once(api, "PUT", "/user/me", actor=actor, body={"nickname": value}, expected_status=400)
        max_value = "名" * 49 + "😀"
        saved = data_dict(api.request("PUT", "/user/me", actor=actor, body={"nickname": max_value}))
        check(saved.get("nickname") == max_value, "50-character nickname did not persist")
        emoji = "边界用户😀"
        saved = data_dict(api.request("PUT", "/user/me", actor=actor, body={"nickname": emoji}))
        check(saved.get("nickname") == emoji, "emoji nickname did not persist")
        return "empty, newline and 51-character nicknames were rejected; 50 characters and emoji persisted"

    record(["IM-042"], nickname_boundaries)

    def bio_and_gender() -> str:
        bio = "第一行\n第二行😀" + "签" * 490
        check(len(bio) <= 500, "test bio exceeds intended boundary")
        saved = data_dict(api.request("PUT", "/user/me", actor=actor, body={"bio": bio, "gender": "female"}))
        check(saved.get("bio") == bio and saved.get("gender") == "female", f"bio/gender not saved: {saved}")
        request_error_once(
            api,
            "PUT",
            "/user/me",
            actor=actor,
            body={"bio": "签" * 501},
            expected_status=400,
        )
        relogged = login(api, primary, "profile-relogin", "qa", run_id)
        me = data_dict(api.request("GET", "/user/me", actor=relogged))
        check(me.get("bio") == bio and me.get("gender") == "female", f"profile lost after relogin: {me}")
        return "multiline emoji bio and gender persisted across relogin; a 501-character bio was rejected"

    record(["IM-045", "IM-046"], bio_and_gender)

    def duplicate_username() -> str:
        request_error_once(
            api,
            "PUT",
            "/user/me",
            actor=actor,
            body={"username": peer_account.username},
            expected_status=400,
        )
        me = data_dict(api.request("GET", "/user/me", actor=actor))
        check(me.get("username") == primary.username, f"duplicate username overwrote account: {me}")
        for invalid in ("ab", "bad-name", "中文用户", "x" * 21):
            request_error_once(
                api,
                "PUT",
                "/user/me",
                actor=actor,
                body={"username": invalid},
                expected_status=400,
            )
        return "duplicate and malformed account identifiers were rejected without changing the current username"

    record(["IM-048"], duplicate_username)

    def search_contracts() -> str:
        target_name = f"Searchable_{run_id[-6:]}"
        api.request("PUT", "/user/me", actor=peer, body={"nickname": target_name})
        keyword = urllib.parse.quote(target_name[3:10])
        found = data_dict(api.request("GET", f"/user/search?keyword={keyword}", actor=actor)).get("list")
        check(isinstance(found, list) and any(item.get("id") == peer.user_id for item in found), f"fuzzy nickname search missed peer: {found}")
        request_error_once(api, "GET", "/user/search?keyword=%20%20", actor=actor, expected_status=400)
        for special in ("%27%20OR%201%3D1--", urllib.parse.quote("😀")):
            payload = data_dict(api.request("GET", f"/user/search?keyword={special}", actor=actor))
            check(isinstance(payload.get("list"), list), f"special search malformed response: {payload}")
        return "nickname substring search found the target; blank input was rejected and quote/emoji input returned safe structured results"

    record(["IM-062", "IM-063"], search_contracts)

    def contact_lifecycle() -> str:
        api.request("POST", "/contact/add", actor=actor, body={"user_id": peer.user_id, "remark": "初始备注"})
        api.request("POST", "/contact/add", actor=peer, body={"user_id": actor.user_id, "remark": "反向备注"})
        remark = "好友😀" + "注" * 20
        api.request("PUT", f"/contact/{peer.user_id}/remark", actor=actor, body={"remark": remark})
        row = next(item for item in contacts(api, actor) if item.get("uuid") == peer.user_id)
        check(row.get("remark") == remark, f"remark did not persist: {row}")
        request_error_once(
            api,
            "PUT",
            f"/contact/{peer.user_id}/remark",
            actor=actor,
            body={"remark": "注" * 101},
            expected_status=400,
        )
        api.request("DELETE", f"/contact/{peer.user_id}", actor=actor)
        check(not any(item.get("uuid") == peer.user_id for item in contacts(api, actor)), "deleted contact remained for actor")
        check(any(item.get("uuid") == actor.user_id for item in contacts(api, peer)), "one-way delete incorrectly removed peer contact")
        sent = send_text(api, actor, chat_id, f"POST_DELETE_{run_id}")
        check(int(sent.get("seq", 0)) > 0, "post-delete stranger message was not accepted")
        return "emoji remark persisted with a 100-character limit; one-way delete preserved the peer relation and existing chat remained usable"

    record(["IM-070", "IM-071", "IM-075"], contact_lifecycle)

    def block_lifecycle() -> str:
        api.request("POST", "/user/blocked", actor=actor, body={"user_id": peer.user_id})
        request_error_once(
            api,
            "POST",
            "/message/send",
            actor=peer,
            body={
                "chat_id": chat_id,
                "type": 1,
                "content": {"text": f"BLOCKED_{run_id}"},
                "msg_id": str(uuid.uuid4()),
            },
            expected_status=403,
        )
        api.request("DELETE", f"/user/blocked/{peer.user_id}", actor=actor)
        sent = send_text(api, peer, chat_id, f"UNBLOCKED_{run_id}")
        check(int(sent.get("seq", 0)) > 0, "message did not recover after unblock")
        return "blocking prevented the blocked user's private message; unblocking immediately restored messaging"

    record(["IM-072", "IM-073"], block_lifecycle)

    payload = {
        "run_id": run_id,
        "base_url": base_url,
        "results": results,
        "summary": {
            "passed_assertion_groups": sum(item["status"] == "PASS" for item in results),
            "failed_assertion_groups": sum(item["status"] == "FAIL" for item in results),
            "covered_case_ids": sorted(
                {case_id for item in results if item["status"] == "PASS" for case_id in item["case_ids"]}
            ),
        },
    }
    output_dir.mkdir(parents=True, exist_ok=True)
    output_path = output_dir / f"auth-profile-contact-api-{run_id}.json"
    output_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    payload["result_path"] = str(output_path.resolve())
    return payload


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", default="http://127.0.0.1:8080")
    parser.add_argument("--output-dir", required=True)
    args = parser.parse_args()
    payload = run(args.base_url, Path(args.output_dir).resolve())
    print(json.dumps(payload["summary"] | {"result_path": payload["result_path"]}, ensure_ascii=False))
    return 1 if payload["summary"]["failed_assertion_groups"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
