#!/usr/bin/env python3
"""Audit counterpart-visible private chat history without exposing its token."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from urllib.parse import urlencode
from urllib.request import Request, urlopen


def get_json(base: str, path: str, token: str) -> dict:
    request = Request(
        f"{base.rstrip('/')}{path}",
        headers={"Authorization": f"Bearer {token}", "Accept": "application/json", "User-Agent": "IM400-Dual-QA/1.0"},
        method="GET",
    )
    with urlopen(request, timeout=30) as response:
        return json.loads(response.read().decode("utf-8"))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--credentials", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--base", default="https://api.example.com/api/v1")
    args = parser.parse_args()

    credentials = json.loads(Path(args.credentials).read_text(encoding="utf-8-sig"))
    token = credentials["token"]
    listing = get_json(args.base, "/chat/list?page=1&page_size=100", token)
    chats = (listing.get("data") or {}).get("list") or []
    audited = []
    for chat in chats:
        if int(chat.get("type") or 0) != 1:
            continue
        chat_id = chat.get("chat_id")
        if not chat_id:
            continue
        query = urlencode({"chat_id": chat_id, "limit": 100})
        response = get_json(args.base, f"/message/list?{query}", token)
        messages = response.get("data") or []
        target_uuid = chat.get("target_uuid")
        target_user = {}
        if target_uuid:
            target_response = get_json(args.base, f"/user/{target_uuid}", token)
            target_user = target_response.get("data") or {}
        audited.append(
            {
                "chat_id": chat_id,
                "name": chat.get("name"),
                "target_uuid": target_uuid,
                "target_username": target_user.get("username"),
                "target_nickname": target_user.get("nickname") or target_user.get("name"),
                "last_msg_text": chat.get("last_msg_text"),
                "last_msg_seq": chat.get("last_msg_seq"),
                "messages": [
                    {
                        "msg_id": item.get("msg_id"),
                        "seq": item.get("seq"),
                        "sender_id": item.get("sender_id"),
                        "text": (item.get("content") or {}).get("text"),
                    }
                    for item in messages
                ],
            }
        )

    result = {"private_chat_count": len(audited), "private_chats": audited}
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"private_chat_count": len(audited), "output": str(output)}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
