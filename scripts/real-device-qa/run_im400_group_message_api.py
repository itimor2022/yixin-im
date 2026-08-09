#!/usr/bin/env python3
"""Batch J local API regression for remaining message and group cases."""

from __future__ import annotations

import argparse
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
    ApiError,
    check,
    create_actor,
    create_chat,
    get_messages,
    list_items,
    response_data,
    send_text,
)


def chat_list(api: Api, actor: Actor) -> list[dict[str, Any]]:
    return list_items(api.request("GET", "/chat/list?page=1&page_size=100", actor=actor))


def chat_list_item(api: Api, actor: Actor, chat_id: str) -> dict[str, Any]:
    for item in chat_list(api, actor):
        if item.get("chat_id") == chat_id:
            return item
    raise AssertionError(f"chat {chat_id} missing from {actor.name} list")


def get_chat(api: Api, actor: Actor, chat_id: str) -> dict[str, Any]:
    data = response_data(api.request("GET", f"/chat/{chat_id}", actor=actor))
    check(isinstance(data, dict), f"chat detail is invalid: {data}")
    return data


def get_members(api: Api, actor: Actor, chat_id: str) -> list[dict[str, Any]]:
    return list_items(
        api.request(
            "GET",
            f"/chat/{chat_id}/members?page=1&page_size=100",
            actor=actor,
        )
    )


def expect_rejection(
    api: Api,
    method: str,
    path: str,
    *,
    actor: Actor,
    body: dict[str, Any] | None = None,
    code: int,
) -> None:
    try:
        api.request(method, path, actor=actor, body=body)
    except ApiError as error:
        actual_code = int(error.payload.get("code", error.status))
        check(actual_code == code, f"expected rejection code {code}, got {actual_code}: {error.payload}")
        return
    raise AssertionError(f"{method} {path} unexpectedly succeeded")


def run(base_url: str, output_dir: Path) -> dict[str, Any]:
    api = Api(base_url.rstrip("/") + "/api/v1")
    run_id = f"{int(time.time())}-{uuid.uuid4().hex[:6]}"
    a, b, c = [create_actor(api, label, run_id) for label in ("A", "B", "C")]
    results: list[dict[str, Any]] = []

    def passed(case_ids: list[str], detail: str) -> None:
        results.append({"case_ids": case_ids, "status": "PASS", "detail": detail})

    chat_ab = create_chat(api, a, 1, [b])
    chat_ac = create_chat(api, a, 1, [c])
    source_one = send_text(api, a, chat_ab, f"BUNDLE_ONE_{run_id}")
    source_two = send_text(api, b, chat_ab, f"BUNDLE_TWO_{run_id}")
    bundle_client_id = str(uuid.uuid4())
    bundle_payload = {
        "chat_id": chat_ac,
        "type": 14,
        "content": {},
        "msg_id": bundle_client_id,
        "source_chat_id": chat_ab,
        "source_msg_ids": [source_two["msg_id"], source_one["msg_id"], source_two["msg_id"]],
    }
    bundle = response_data(api.request("POST", "/message/send", actor=a, body=bundle_payload))
    check(isinstance(bundle, dict), "forward bundle response is invalid")
    bundle_items = bundle.get("content", {}).get("forward_bundle", {}).get("items", [])
    check(
        [item.get("source_message_id") for item in bundle_items]
        == [source_one["msg_id"], source_two["msg_id"]],
        f"forward bundle did not deduplicate and restore source seq order: {bundle_items}",
    )
    retry = response_data(api.request("POST", "/message/send", actor=a, body=bundle_payload))
    check(isinstance(retry, dict) and retry.get("msg_id") == bundle.get("msg_id"), "forward bundle retry did not reuse the original message")
    target_bundles = [item for item in get_messages(api, c, chat_ac) if item.get("type") == 14]
    check(len(target_bundles) == 1, f"forward bundle retry created duplicates: {len(target_bundles)}")
    forbidden_payload = dict(bundle_payload)
    forbidden_payload["msg_id"] = str(uuid.uuid4())
    api.request("POST", "/message/send", actor=c, body=forbidden_payload, expected_status=403)
    passed(["IM-199"], "server-authored bundle deduplicated source ids, restored seq order, rejected source non-members and retried idempotently")

    revoke_target = send_text(api, a, chat_ab, f"REVOKE_UNREAD_{run_id}")
    before_revoke = chat_list_item(api, b, chat_ab)
    before_unread = int(before_revoke.get("unread_count", 0))
    check(before_unread > 0, f"recipient had no unread message before revoke: {before_revoke}")
    api.request(
        "POST",
        "/message/revoke",
        actor=a,
        body={"chat_id": chat_ab, "msg_id": revoke_target["msg_id"]},
    )
    after_revoke = chat_list_item(api, b, chat_ab)
    after_unread = int(after_revoke.get("unread_count", 0))
    check(after_unread == before_unread - 1, f"revoke did not decrement recipient unread count: before={before_unread}, after={after_unread}")
    api.request(
        "POST",
        "/message/revoke",
        actor=a,
        body={"chat_id": chat_ab, "msg_id": revoke_target["msg_id"]},
    )
    after_retry_unread = int(chat_list_item(api, b, chat_ab).get("unread_count", 0))
    check(
        after_retry_unread == after_unread,
        f"idempotent revoke retry decremented unread twice: first={after_unread}, retry={after_retry_unread}",
    )
    revoked_message = next(
        (item for item in get_messages(api, b, chat_ab) if item.get("msg_id") == revoke_target["msg_id"]),
        None,
    )
    check(isinstance(revoked_message, dict) and revoked_message.get("is_revoked") is True, "immediate history did not expose the revoked state")
    check(after_revoke.get("last_msg_text") == "有人撤回了一条消息", f"recipient preview was not corrected: {after_revoke}")
    passed(["IM-205"], "revoke immediately updated history, preview and unread exactly once across an idempotent retry")

    group_id = create_chat(api, a, 2, [b, c], f"IM400_J_{run_id}"[:32])

    api.request("PUT", f"/chat/{group_id}", actor=b, body={"name": "DENIED"}, expected_status=403)
    valid_name = f"Group J {run_id}"[:32]
    valid_description = f"Batch J description {run_id}"
    updated_group = response_data(
        api.request(
            "PUT",
            f"/chat/{group_id}",
            actor=a,
            body={"name": f"  {valid_name}  ", "description": f"  {valid_description}  "},
        )
    )
    check(
        isinstance(updated_group, dict)
        and updated_group.get("name") == valid_name
        and updated_group.get("description") == valid_description,
        f"group profile normalization failed: {updated_group}",
    )
    observed_group = get_chat(api, c, group_id)
    check(observed_group.get("name") == valid_name, f"member did not observe the new group name: {observed_group}")
    passed(["IM-261"], "owner rename was normalized and immediately visible to another member; ordinary member mutation was denied")

    api.request("PUT", f"/chat/{group_id}", actor=a, body={"name": " "}, expected_status=400)
    api.request("PUT", f"/chat/{group_id}", actor=a, body={"name": "X" * 33}, expected_status=400)
    passed(["IM-262"], "server rejected blank and 33-character group names")

    api.request("PUT", f"/chat/{group_id}", actor=a, body={"description": "   "}, expected_status=400)
    api.request("PUT", f"/chat/{group_id}", actor=a, body={"description": "D" * 1001}, expected_status=400)
    cleared_group = response_data(
        api.request("PUT", f"/chat/{group_id}", actor=a, body={"description": ""})
    )
    check(isinstance(cleared_group, dict) and cleared_group.get("description") == "", f"description clear failed: {cleared_group}")
    passed(["IM-267"], "description accepted explicit clear and rejected whitespace-only and over-1000-character values")

    api.request(
        "POST",
        f"/chat/{group_id}/announcements",
        actor=b,
        body={"content": "DENIED"},
        expected_status=403,
    )
    announcement = response_data(
        api.request(
            "POST",
            f"/chat/{group_id}/announcements",
            actor=a,
            body={"content": f"Announcement {run_id}"},
        )
    )
    check(isinstance(announcement, dict) and int(announcement.get("id", 0)) > 0, f"announcement create failed: {announcement}")
    announcement_id = int(announcement["id"])
    first_ack = response_data(
        api.request("POST", f"/chat/{group_id}/announcements/{announcement_id}/acknowledge", actor=b, body={})
    )
    duplicate_ack = response_data(
        api.request("POST", f"/chat/{group_id}/announcements/{announcement_id}/acknowledge", actor=b, body={})
    )
    check(
        isinstance(first_ack, dict)
        and isinstance(duplicate_ack, dict)
        and first_ack.get("acknowledged_count") == duplicate_ack.get("acknowledged_count"),
        f"duplicate acknowledgement was not idempotent: first={first_ack}, duplicate={duplicate_ack}",
    )
    api.request("POST", f"/chat/{group_id}/announcements/{announcement_id}/acknowledge", actor=c, body={})
    announcement_items = list_items(
        api.request("GET", f"/chat/{group_id}/announcements?page=1&page_size=20", actor=a)
    )
    announcement_view = next((item for item in announcement_items if int(item.get("id", 0)) == announcement_id), None)
    check(
        isinstance(announcement_view, dict)
        and int(announcement_view.get("acknowledged_count", 0)) == 3
        and int(announcement_view.get("member_count", 0)) == 3,
        f"announcement acknowledgement progress is invalid: {announcement_view}",
    )
    passed(["IM-266"], "announcement publish permission and idempotent 3-of-3 acknowledgement progress passed")

    api.request(
        "PUT",
        f"/chat/{group_id}/members/{b.user_id}/nickname",
        actor=b,
        body={"nickname": "  BobLocal  "},
    )
    api.request(
        "PUT",
        f"/chat/{group_id}/members/{b.user_id}/nickname",
        actor=b,
        body={"nickname": "N" * 33},
        expected_status=400,
    )
    passed(["IM-268"], "ordinary member updated their own normalized group nickname and the server enforced the 32-character limit")

    api.request(
        "PUT",
        f"/chat/{group_id}/members/{b.user_id}/nickname",
        actor=c,
        body={"nickname": "DENIED"},
        expected_status=403,
    )
    api.request(
        "PUT",
        f"/chat/{group_id}/members/{c.user_id}/nickname",
        actor=a,
        body={"nickname": "CarolByOwner"},
    )
    member_map = {str(item.get("user_id")): item for item in get_members(api, a, group_id)}
    check(member_map.get(b.user_id, {}).get("nickname_in_chat") == "BobLocal", f"B nickname did not persist: {member_map.get(b.user_id)}")
    check(member_map.get(c.user_id, {}).get("nickname_in_chat") == "CarolByOwner", f"C nickname did not persist: {member_map.get(c.user_id)}")
    passed(["IM-269"], "owner changed an ordinary member nickname while peer-to-peer nickname mutation was denied")

    send_text(api, b, group_id, f"DENIED_MENTION_ALL_{run_id}", mention_all=True, expected_status=403)
    mention_all_message = send_text(api, a, group_id, f"MENTION_ALL_{run_id}", mention_all=True)
    check("__all__" in (mention_all_message.get("mentions") or []), f"mention-all sentinel missing: {mention_all_message}")
    mention_all_matches = [item for item in get_messages(api, c, group_id) if item.get("msg_id") == mention_all_message.get("msg_id")]
    check(len(mention_all_matches) == 1, f"mention-all message was missing or duplicated: {mention_all_matches}")
    passed(["IM-285"], "ordinary member mention-all was denied and owner mention-all persisted exactly once with the authoritative sentinel")

    other_sender_message = send_text(api, c, group_id, f"ADMIN_REVOKE_{run_id}")
    expect_rejection(
        api,
        "POST",
        "/message/revoke",
        actor=b,
        body={"chat_id": group_id, "msg_id": other_sender_message["msg_id"]},
        code=400,
    )
    api.request(
        "POST",
        "/message/revoke",
        actor=a,
        body={"chat_id": group_id, "msg_id": other_sender_message["msg_id"]},
    )
    revoked_by_owner = next(
        (item for item in get_messages(api, c, group_id) if item.get("msg_id") == other_sender_message["msg_id"]),
        None,
    )
    check(
        isinstance(revoked_by_owner, dict)
        and revoked_by_owner.get("is_revoked") is True
        and revoked_by_owner.get("revoked_by") == a.user_id,
        f"owner revoke state is invalid: {revoked_by_owner}",
    )
    passed(["IM-292"], "ordinary member could not revoke a peer message; owner revoke was immediately authoritative with revoked_by")

    receipt_message = send_text(api, a, group_id, f"RECEIPT_{run_id}")
    api.request(
        "POST",
        "/message/read",
        actor=b,
        body={"chat_id": group_id, "msg_seq": int(receipt_message["seq"])},
    )
    receipt_query = urllib.parse.urlencode({"chat_id": group_id, "msg_id": receipt_message["msg_id"]})
    ordinary_detail = response_data(api.request("GET", f"/message/detail?{receipt_query}", actor=b))
    owner_detail = response_data(api.request("GET", f"/message/detail?{receipt_query}", actor=a))
    ordinary_receipts = ordinary_detail.get("receipts", {}) if isinstance(ordinary_detail, dict) else {}
    owner_receipts = owner_detail.get("receipts", {}) if isinstance(owner_detail, dict) else {}
    check(
        ordinary_receipts.get("can_view_members") is False and ordinary_receipts.get("members") == [],
        f"ordinary member received protected receipt members: {ordinary_receipts}",
    )
    check(
        owner_receipts.get("can_view_members") is True
        and int(owner_receipts.get("read_count", 0)) >= 1
        and any(item.get("user_id") == b.user_id and item.get("read") is True for item in owner_receipts.get("members", [])),
        f"owner receipt detail is incomplete: {owner_receipts}",
    )
    passed(["IM-293"], "receipt totals reflected B's read cursor while per-member receipt identities remained owner/admin-only")

    search_text = f"SEARCH_TARGET_{run_id}"
    search_message = send_text(api, c, group_id, search_text)
    search_query = urllib.parse.urlencode({"keyword": search_text})
    search_items = list_items(api.request("GET", f"/chat/{group_id}/search?{search_query}", actor=b))
    search_hit = next((item for item in search_items if item.get("msg_id") == search_message.get("msg_id")), None)
    check(
        isinstance(search_hit, dict) and int(search_hit.get("seq", 0)) == int(search_message.get("seq", 0)),
        f"search result did not preserve target message id/seq: {search_hit}",
    )
    passed(["IM-298"], "group search returned the exact target message id and authoritative sequence")

    api.request("PUT", f"/chat/{group_id}/members/{b.user_id}/role", actor=a, body={"role": 1})
    promoted_members = {str(item.get("user_id")): item for item in get_members(api, a, group_id)}
    check(promoted_members.get(b.user_id, {}).get("role") == 2, f"admin promotion was not visible: {promoted_members.get(b.user_id)}")
    api.request("PUT", f"/chat/{group_id}/members/{b.user_id}/role", actor=a, body={"role": 0})
    api.request("PUT", f"/chat/{group_id}", actor=a, body={"can_send_message": False})
    send_text(api, b, group_id, f"DENIED_MUTED_{run_id}", expected_status=403)
    send_text(api, a, group_id, f"OWNER_ALLOWED_{run_id}")
    api.request("PUT", f"/chat/{group_id}", actor=a, body={"can_send_message": True})
    audit_messages_before_leave = [item for item in get_messages(api, a, group_id) if int(item.get("type", 0)) == 99]
    check(len(audit_messages_before_leave) >= 6, f"expected group audit messages for profile/role/permission/nickname actions, got {len(audit_messages_before_leave)}")
    passed(["IM-280"], "rename, nickname, role and all-member mute changes produced durable system audit messages")

    api.request("POST", f"/chat/{group_id}/leave", actor=b, body={})
    after_leave_group = get_chat(api, a, group_id)
    check(int(after_leave_group.get("member_count", 0)) == 2, f"member count did not decrement after leave: {after_leave_group}")
    send_text(api, b, group_id, f"AFTER_LEAVE_{run_id}", expected_status=403)
    api.request("GET", f"/chat/{group_id}/search?{search_query}", actor=b, expected_status=403)
    audit_messages_after_leave = [item for item in get_messages(api, a, group_id) if int(item.get("type", 0)) == 99]
    check(len(audit_messages_after_leave) == len(audit_messages_before_leave) + 1, "leave did not append exactly one system audit message")
    passed(["IM-249"], "leave decremented authoritative member_count, appended one audit message and immediately revoked message/search access")

    report = {
        "run_id": run_id,
        "base_url": base_url,
        "actors": [{"name": actor.name, "user_id": actor.user_id} for actor in (a, b, c)],
        "chat_ids": {"private_ab": chat_ab, "private_ac": chat_ac, "group": group_id},
        "results": results,
        "summary": {
            "passed_assertion_groups": len(results),
            "covered_case_ids": sorted({case_id for result in results for case_id in result["case_ids"]}),
        },
    }
    output_dir.mkdir(parents=True, exist_ok=True)
    report_path = output_dir / f"group-message-api-{run_id}.json"
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
