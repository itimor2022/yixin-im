#!/usr/bin/env python3
"""Create a writable QA private chat and seed it without printing credentials."""

from __future__ import annotations

import argparse
import json
import time
import uuid
from pathlib import Path
from urllib.parse import urlencode
from urllib.request import Request, urlopen


def request_json(base: str, method: str, path: str, token: str, payload: dict | None = None) -> dict:
    body = None if payload is None else json.dumps(payload, ensure_ascii=False).encode("utf-8")
    headers = {"Accept": "application/json", "User-Agent": "IM400-Dual-QA/1.0"}
    if body is not None:
        headers["Content-Type"] = "application/json"
    headers["Authorization"] = f"Bearer {token}"
    with urlopen(Request(f"{base.rstrip('/')}{path}", data=body, headers=headers, method=method), timeout=30) as response:
        return json.loads(response.read().decode("utf-8"))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--credentials", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--target", default="smoke_bob")
    parser.add_argument("--base", default="https://api.example.com/api/v1")
    args = parser.parse_args()

    credentials = json.loads(Path(args.credentials).read_text(encoding="utf-8-sig"))
    token = credentials["token"]
    query = urlencode({"keyword": args.target})
    search = request_json(args.base, "GET", f"/user/search?{query}", token)
    users = (search.get("data") or {}).get("list") or []
    target = next((item for item in users if item.get("username") == args.target), None)
    if target is None:
        raise RuntimeError(f"target account not found: {args.target}")

    created = request_json(
        args.base,
        "POST",
        "/chat/create",
        token,
        {"type": 1, "member_ids": [target["id"]]},
    )
    chat = created.get("data") or {}
    chat_id = chat.get("uuid")
    if not chat_id:
        raise RuntimeError(f"chat creation did not return uuid: code={created.get('code')}")

    marker = f"QA-SEED-{time.strftime('%H%M%S')}"
    send = request_json(
        args.base,
        "POST",
        "/message/send",
        token,
        {
            "chat_id": chat_id,
            "type": 1,
            "content": {"text": marker},
            "msg_id": str(uuid.uuid4()),
        },
    )
    if int(send.get("code", -1)) != 0:
        raise RuntimeError(f"seed message failed: code={send.get('code')}, message={send.get('message')}")

    result = {
        "created_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "counterpart_username": credentials.get("username"),
        "counterpart_nickname": credentials.get("nickname"),
        "target_username": target.get("username"),
        "target_nickname": target.get("nickname"),
        "target_uuid": target.get("id"),
        "chat_uuid": chat_id,
        "seed_marker": marker,
        "send_code": send.get("code"),
    }
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"chat_created": True, "seed_marker": marker, "output": str(output)}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
