#!/usr/bin/env python3
"""Initialize and verify the isolated dual-device QA account without leaking secrets."""

from __future__ import annotations

import json
import time
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


REPO = Path(__file__).resolve().parents[2]
BACKEND = "https://api.example.com/api/v1"
SOURCE = REPO / "artifacts/real-device-qa/qa400-counterpart-secret.json"
OUTPUT = REPO / "artifacts/real-device-qa/dual-device-counterpart-login.json"
USERNAME = "qa_dual_8ad75a"
PASSWORD = "DualTest123!"


def request_json(method: str, path: str, payload: dict, token: str = "") -> tuple[int, dict]:
    body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    headers = {"Content-Type": "application/json", "User-Agent": "IM400-Dual-QA/1.0"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    last_error: Exception | None = None
    for attempt in range(5):
        try:
            with urlopen(Request(f"{BACKEND}{path}", data=body, headers=headers, method=method), timeout=20) as response:
                return response.status, json.loads(response.read().decode("utf-8"))
        except HTTPError as exc:
            raw = exc.read().decode("utf-8", errors="replace")
            parsed = json.loads(raw) if raw else {}
            return exc.code, parsed
        except (URLError, TimeoutError, OSError) as exc:
            last_error = exc
            time.sleep(1.5 * (attempt + 1))
    raise RuntimeError(f"request failed after retries: {last_error}")


def login() -> tuple[int, dict]:
    return request_json(
        "POST",
        "/auth/login",
        {
            "username": USERNAME,
            "password": PASSWORD,
            "device_id": "qa-dual-api-verify",
            "device_type": "android",
            "device_name": "QA Dual Verify",
        },
    )


def main() -> None:
    source = json.loads(SOURCE.read_text(encoding="utf-8-sig"))
    bootstrap_token = source["data"]["token"]

    status, result = login()
    if status != 200 or int(result.get("code", -1)) != 0:
        init_status, init_result = request_json(
            "PUT",
            "/auth/initialize-credentials",
            {"username": USERNAME, "password": PASSWORD},
            bootstrap_token,
        )
        if init_status not in (200, 409):
            raise RuntimeError(f"initialize failed: HTTP {init_status}, code={init_result.get('code')}")
        status, result = login()

    data = result.get("data") or {}
    if status != 200 or int(result.get("code", -1)) != 0 or not data.get("token"):
        raise RuntimeError(f"login verification failed: HTTP {status}, code={result.get('code')}")
    user = data.get("user") or {}
    output = {
        "username": USERNAME,
        "password": PASSWORD,
        "uuid": user.get("uuid"),
        "nickname": user.get("nickname"),
        "token": data.get("token"),
        "verified_http": status,
        "verified_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
    }
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(output, ensure_ascii=False, indent=2), encoding="utf-8")
    print("Counterpart credentials are initialized and API login is verified.")
    print(f"Username: {USERNAME}")
    print(f"UUID: {user.get('uuid')}")
    print(f"Artifact: {OUTPUT}")


if __name__ == "__main__":
    main()
