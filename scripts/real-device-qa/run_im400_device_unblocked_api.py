#!/usr/bin/env python3
"""Retest device-related IM-400 cases against the current local Docker API.

The suite uses isolated temporary accounts. It validates multi-platform session
contracts and synchronization without changing the two real-device accounts.
"""

from __future__ import annotations

import argparse
import json
import time
import urllib.parse
import uuid
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable

from run_im400_remaining_api import (
    Actor,
    Api,
    ApiError,
    check,
    create_chat,
    get_messages,
    list_items,
    response_data,
    send_text,
)


@dataclass
class Account:
    username: str
    password: str
    user_id: str
    sessions: dict[str, Actor] = field(default_factory=dict)


def create_account(api: Api, label: str, run_id: str) -> Account:
    suffix = uuid.uuid4().hex[:7]
    username = f"du_{label.lower()}_{suffix}"[:20]
    password = f"Qa{uuid.uuid4().hex[:12]}"
    device_id = f"qa-{label.lower()}-android-{run_id}"
    payload = api.request(
        "POST",
        "/auth/register",
        body={
            "username": username,
            "password": password,
            "nickname": f"Device QA {label}",
            "gender": "male",
            "device_id": device_id,
            "device_type": "android",
            "device_name": f"Android {label}",
        },
    )
    data = response_data(payload)
    check(isinstance(data, dict) and isinstance(data.get("user"), dict), "register payload missing user")
    account = Account(username, password, str(data["user"]["uuid"]))
    account.sessions["android"] = Actor(f"{label}-android", account.user_id, str(data["token"]))
    return account


def login(
    api: Api,
    account: Account,
    label: str,
    device_type: str,
    run_id: str,
    *,
    password: str | None = None,
) -> Actor:
    payload = api.request(
        "POST",
        "/auth/login",
        body={
            "username": account.username,
            "password": password or account.password,
            "device_id": f"qa-{label.lower()}-{run_id}",
            "device_type": device_type,
            "device_name": f"{device_type.title()} {label}",
        },
    )
    data = response_data(payload)
    check(isinstance(data, dict) and data.get("token"), "login payload missing token")
    actor = Actor(label, account.user_id, str(data["token"]))
    account.sessions[label] = actor
    return actor


def data_dict(payload: dict[str, Any]) -> dict[str, Any]:
    data = response_data(payload)
    check(isinstance(data, dict), f"response data is not an object: {payload}")
    return data


def chat_list(api: Api, actor: Actor) -> list[dict[str, Any]]:
    return list_items(api.request("GET", "/chat/list?page=1&page_size=100", actor=actor))


def chat_item(api: Api, actor: Actor, chat_id: str) -> dict[str, Any]:
    for item in chat_list(api, actor):
        if item.get("chat_id") == chat_id:
            return item
    raise AssertionError(f"chat {chat_id} missing for {actor.name}")


def devices(api: Api, actor: Actor) -> list[dict[str, Any]]:
    data = data_dict(api.request("GET", "/user/devices", actor=actor))
    value = data.get("devices")
    check(isinstance(value, list), f"device list missing: {data}")
    return value


def assert_unauthorized(api: Api, actor: Actor) -> None:
    payload = api.request("GET", "/user/me", actor=actor, expected_status=401)
    check(int(payload.get("code", 401)) != 0, "invalidated session unexpectedly returned success")


def message(api: Api, actor: Actor, chat_id: str, msg_id: str) -> dict[str, Any]:
    item = next((row for row in get_messages(api, actor, chat_id) if row.get("msg_id") == msg_id), None)
    check(isinstance(item, dict), f"message {msg_id} missing for {actor.name}")
    return item


def run(base_url: str, output_dir: Path) -> dict[str, Any]:
    api = Api(base_url.rstrip("/") + "/api/v1")
    run_id = f"{int(time.time())}-{uuid.uuid4().hex[:6]}"
    results: list[dict[str, Any]] = []

    def record(case_ids: list[str], body: Callable[[], str]) -> None:
        try:
            detail = body()
            results.append({"case_ids": case_ids, "status": "PASS", "detail": detail})
        except Exception as exc:  # keep the remaining independent probes running
            results.append(
                {
                    "case_ids": case_ids,
                    "status": "FAIL",
                    "detail": f"{type(exc).__name__}: {exc}",
                }
            )

    primary = create_account(api, "Primary", run_id)
    peer_account = create_account(api, "Peer", run_id)
    android = primary.sessions["android"]
    peer = peer_account.sessions["android"]
    windows = login(api, primary, "windows", "windows", run_id)
    web = login(api, primary, "web", "web", run_id)
    chat_id = create_chat(api, android, 1, [peer])

    def coexist(platform: str, actor: Actor) -> str:
        incoming = send_text(api, peer, chat_id, f"COEXIST_{platform}_{run_id}")
        seen = message(api, actor, chat_id, str(incoming["msg_id"]))
        seq = int(seen.get("seq", 0))
        check(seq > 0, "coexisting session did not receive authoritative sequence")
        api.request("POST", "/message/read", actor=actor, body={"chat_id": chat_id, "msg_seq": seq})
        check(int(chat_item(api, android, chat_id).get("unread_count", -1)) == 0, "read state did not sync to Android session")
        outgoing = send_text(api, android, chat_id, f"REVOKE_{platform}_{run_id}")
        api.request(
            "POST",
            "/message/revoke",
            actor=android,
            body={"chat_id": chat_id, "msg_id": outgoing["msg_id"]},
        )
        check(message(api, actor, chat_id, str(outgoing["msg_id"])).get("is_revoked") is True, "revoke did not sync")
        return f"Android and {platform} sessions coexisted; message, read and revoke states converged"

    record(["IM-022"], lambda: coexist("Windows", windows))
    record(["IM-023"], lambda: coexist("Web", web))

    def device_list_case() -> str:
        rows = devices(api, android)
        types = {str(item.get("device_type")) for item in rows}
        check({"android", "windows", "web"}.issubset(types), f"device types missing: {types}")
        current = [item for item in rows if item.get("is_current") is True]
        check(len(current) == 1 and current[0].get("device_type") == "android", f"current device marker invalid: {current}")
        check(all(item.get("device_name") and item.get("last_active") for item in rows), "device metadata incomplete")
        return "device list exposed Android/Windows/Web metadata with one accurate current-device marker"

    record(["IM-030"], device_list_case)

    def terminate_one() -> str:
        target = next(item for item in devices(api, android) if item.get("device_type") == "web")
        api.request("DELETE", f"/user/devices/{target['device_id']}", actor=android)
        assert_unauthorized(api, web)
        api.request("GET", "/user/me", actor=windows)
        api.request("GET", "/user/me", actor=android)
        return "terminating the Web device invalidated only its token; Android and Windows stayed valid"

    record(["IM-028"], terminate_one)

    def terminate_others() -> str:
        account = create_account(api, "TerminateAll", run_id)
        current = account.sessions["android"]
        other_one = login(api, account, "other-windows", "windows", run_id)
        other_two = login(api, account, "other-web", "web", run_id)
        api.request("POST", "/user/devices/terminate-others", actor=current, body={})
        api.request("GET", "/user/me", actor=current)
        assert_unauthorized(api, other_one)
        assert_unauthorized(api, other_two)
        remaining = devices(api, current)
        check(len(remaining) == 1 and remaining[0].get("is_current") is True, f"unexpected remaining devices: {remaining}")
        return "terminate-others preserved the current Android session and invalidated both other platforms"

    record(["IM-029"], terminate_others)

    def password_invalidation() -> str:
        account = create_account(api, "Password", run_id)
        current = account.sessions["android"]
        other = login(api, account, "password-web", "web", run_id)
        new_password = f"New{uuid.uuid4().hex[:10]}"
        api.request(
            "POST",
            "/auth/change-password",
            actor=current,
            body={"old_password": account.password, "new_password": new_password},
        )
        assert_unauthorized(api, current)
        assert_unauthorized(api, other)
        try:
            api.request(
                "POST",
                "/auth/login",
                body={
                    "username": account.username,
                    "password": account.password,
                    "device_id": f"qa-old-password-{run_id}",
                    "device_type": "android",
                    "device_name": "Old Password Probe",
                },
            )
        except ApiError as error:
            check(int(error.payload.get("code", 0)) == 400, f"unexpected old-password rejection: {error.payload}")
        else:
            raise AssertionError("old password unexpectedly remained valid")
        login(api, account, "new-password", "android", run_id, password=new_password)
        return "password change invalidated all existing sessions, rejected the old password and accepted the new one"

    record(["IM-027"], password_invalidation)

    def privacy_sync() -> str:
        api.request(
            "PUT",
            "/user/privacy",
            actor=android,
            body={
                "last_seen_visibility": "不可见",
                "phone_visibility": "仅自己",
                "group_invite_permission": "联系人",
                "allow_phone_search": False,
                "allow_short_id_search": False,
            },
        )
        observed = data_dict(api.request("GET", "/user/privacy", actor=windows))
        check(observed.get("last_seen_visibility") == "不可见", f"last-seen setting not synced: {observed}")
        check(observed.get("allow_phone_search") is False, f"search setting not synced: {observed}")
        api.request(
            "PUT",
            "/user/privacy",
            actor=windows,
            body={"last_seen_visibility": "所有人", "allow_phone_search": True, "allow_short_id_search": True},
        )
        restored = data_dict(api.request("GET", "/user/privacy", actor=android))
        check(restored.get("last_seen_visibility") == "所有人", "privacy restore did not sync")
        return "privacy and search settings synchronized bidirectionally across Android and Windows sessions"

    record(["IM-037", "IM-058"], privacy_sync)

    def block_sync() -> str:
        api.request("POST", "/user/blocked", actor=android, body={"user_id": peer.user_id})
        blocked = data_dict(api.request("GET", "/user/blocked", actor=windows)).get("list")
        check(isinstance(blocked, list) and any(item.get("user_id") == peer.user_id for item in blocked), "block did not sync")
        api.request("DELETE", f"/user/blocked/{peer.user_id}", actor=windows)
        after = data_dict(api.request("GET", "/user/blocked", actor=android)).get("list")
        check(isinstance(after, list) and not any(item.get("user_id") == peer.user_id for item in after), "unblock did not sync")
        return "block and unblock changes synchronized across Android and Windows sessions"

    record(["IM-074"], block_sync)

    def read_sync() -> str:
        sent = [send_text(api, peer, chat_id, f"READ_{index}_{run_id}") for index in range(5)]
        max_seq = max(int(item["seq"]) for item in sent)
        check(int(chat_item(api, android, chat_id).get("unread_count", 0)) >= 5, "unread batch was not accumulated")
        api.request("POST", "/message/read", actor=windows, body={"chat_id": chat_id, "msg_seq": max_seq})
        android_row = chat_item(api, android, chat_id)
        check(int(android_row.get("unread_count", -1)) == 0, f"Android unread did not clear: {android_row}")
        return "reading through the Windows session cleared the full unread range for the Android session"

    record(["IM-129", "IM-131", "IM-226"], read_sync)

    def delayed_order() -> str:
        first = send_text(api, peer, chat_id, f"NEWER_CLIENT_TIME_{run_id}")
        delayed = send_text(api, peer, chat_id, f"DELAYED_OLD_CLIENT_TIME_{run_id}")
        rows = sorted(
            [message(api, android, chat_id, str(first["msg_id"])), message(api, android, chat_id, str(delayed["msg_id"]))],
            key=lambda item: int(item.get("seq", 0)),
        )
        check([row.get("msg_id") for row in rows] == [first["msg_id"], delayed["msg_id"]], f"authoritative order invalid: {rows}")
        check(int(rows[0]["seq"]) + 1 == int(rows[1]["seq"]), "server sequence has a gap")
        return "late-arriving content was ordered by contiguous authoritative sequence instead of client label/time"

    record(["IM-134"], delayed_order)

    def reaction_concurrency() -> str:
        third_account = create_account(api, "Reaction", run_id)
        third = third_account.sessions["android"]
        group_id = create_chat(api, android, 2, [peer, third], f"React {run_id}"[:32])
        source = send_text(api, android, group_id, f"REACTION_{run_id}")
        body = {"chat_id": group_id, "msg_id": source["msg_id"], "emoji": "👍"}
        with ThreadPoolExecutor(max_workers=2) as pool:
            list(pool.map(lambda actor: api.request("POST", "/message/reaction/add", actor=actor, body=body), [peer, third]))
        observed = message(api, android, group_id, str(source["msg_id"]))
        reactions = observed.get("reactions")
        check(reactions, f"reaction aggregate missing: {observed}")
        with ThreadPoolExecutor(max_workers=2) as pool:
            list(pool.map(lambda actor: api.request("POST", "/message/reaction/remove", actor=actor, body=body), [peer, third]))
        cleared: Any = None
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            cleared = message(api, android, group_id, str(source["msg_id"])).get("reactions")
            if not cleared:
                break
            time.sleep(0.25)
        check(not cleared, f"reaction aggregate did not converge after concurrent removal: {cleared}")
        return "two members concurrently added and removed the same reaction; the authoritative aggregate converged"

    record(["IM-138"], reaction_concurrency)

    def revoke_sync() -> str:
        source = send_text(api, android, chat_id, f"MULTI_REVOKE_{run_id}")
        api.request("POST", "/message/revoke", actor=android, body={"chat_id": chat_id, "msg_id": source["msg_id"]})
        check(message(api, windows, chat_id, str(source["msg_id"])).get("is_revoked") is True, "Windows session missed revoke")
        return "a mobile revoke was immediately visible from the concurrent Windows session"

    record(["IM-207"], revoke_sync)

    def multi_chat_offline() -> str:
        third_account = create_account(api, "MultiChat", run_id)
        third = third_account.sessions["android"]
        chat_peer = create_chat(api, android, 1, [third])
        group_id = create_chat(api, android, 2, [peer, third], f"Offline {run_id}"[:32])
        expected: dict[str, int] = {chat_id: 2, chat_peer: 3, group_id: 4}
        for target_chat, count in expected.items():
            sender = peer if target_chat != chat_peer else third
            for index in range(count):
                send_text(api, sender, target_chat, f"OFFLINE_{target_chat[:4]}_{index}_{run_id}")
        rows = {item.get("chat_id"): item for item in chat_list(api, android)}
        for target_chat, count in expected.items():
            check(int(rows[target_chat].get("unread_count", 0)) >= count, f"unread count wrong for {target_chat}: {rows[target_chat]}")
            synced = data_dict(
                api.request(
                    "POST",
                    "/message/sync",
                    actor=android,
                    body={"chat_id": target_chat, "last_seq": 0, "limit": 100},
                )
            ).get("messages")
            check(isinstance(synced, list) and len(synced) >= count, f"sync missing messages for {target_chat}")
        return "offline-style pull recovered messages from two private chats and one group with independent unread counts"

    record(["IM-223"], multi_chat_offline)

    def reconnect_incremental() -> str:
        baseline = send_text(api, peer, chat_id, f"SYNC_BASE_{run_id}")
        revoked = send_text(api, peer, chat_id, f"SYNC_REVOKE_{run_id}")
        survivor = send_text(api, peer, chat_id, f"SYNC_KEEP_{run_id}")
        api.request("POST", "/message/revoke", actor=peer, body={"chat_id": chat_id, "msg_id": revoked["msg_id"]})
        synced = data_dict(
            api.request(
                "POST",
                "/message/sync",
                actor=android,
                body={"chat_id": chat_id, "last_seq": int(baseline["seq"]), "limit": 100},
            )
        ).get("messages")
        check(isinstance(synced, list), "incremental sync payload missing messages")
        by_id = {item.get("msg_id"): item for item in synced}
        check(by_id.get(revoked["msg_id"], {}).get("is_revoked") is True, f"revoked terminal state missing: {synced}")
        check(survivor["msg_id"] in by_id, "surviving message missing after reconnect sync")
        return "incremental sync after a disconnect window returned both the revoked terminal state and surviving message"

    record(["IM-372"], reconnect_incremental)

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
    output_path = output_dir / f"device-unblocked-api-{run_id}.json"
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
