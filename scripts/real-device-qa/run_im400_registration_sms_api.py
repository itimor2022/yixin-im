#!/usr/bin/env python3
"""Validate local-only SMS registration contracts without external delivery."""

from __future__ import annotations

import argparse
import json
import subprocess
import time
import urllib.error
import urllib.request
from datetime import datetime
from pathlib import Path
from typing import Any


class ApiError(RuntimeError):
    def __init__(self, method: str, path: str, status: int, payload: dict[str, Any]):
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
        body: dict[str, Any] | None = None,
        token: str | None = None,
    ) -> dict[str, Any]:
        data = None if body is None else json.dumps(body).encode("utf-8")
        headers = {"Accept": "application/json"}
        if body is not None:
            headers["Content-Type"] = "application/json"
        if token:
            headers["Authorization"] = f"Bearer {token}"
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
        try:
            payload = json.loads(raw) if raw else {}
        except json.JSONDecodeError:
            payload = {"raw": raw}
        if status >= 400 or payload.get("code") != 0:
            raise ApiError(method, path, status, payload)
        return payload


def check(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def expect_error(
    action: Any,
    *,
    codes: set[int],
    message_fragment: str | None = None,
) -> ApiError:
    try:
        action()
    except ApiError as error:
        business_code = int(error.payload.get("code", error.status))
        check(business_code in codes, f"unexpected error code: {error.payload}")
        if message_fragment:
            check(
                message_fragment in str(error.payload.get("message", "")),
                f"missing error text {message_fragment!r}: {error.payload}",
            )
        return error
    raise AssertionError("request unexpectedly succeeded")


def redis(*args: str) -> str:
    completed = subprocess.run(
        ["docker", "exec", "genericim-redis", "redis-cli", "--raw", *args],
        text=True,
        encoding="utf-8",
        errors="replace",
        capture_output=True,
        timeout=20,
        check=False,
    )
    if completed.returncode != 0:
        raise RuntimeError(f"redis-cli failed: {completed.stderr.strip()}")
    return completed.stdout.strip()


def code_key(phone: str) -> str:
    return f"auth:register:sms:{phone}"


def send_code(api: Api, phone: str) -> str:
    api.request("POST", "/auth/register/send-code", body={"phone": phone})
    raw_code = redis("GET", code_key(phone))
    try:
        decoded = json.loads(raw_code)
        code = decoded if isinstance(decoded, str) else raw_code
    except json.JSONDecodeError:
        code = raw_code
    check(len(code) == 6 and code.isdigit(), "registration code was not stored locally")
    ttl = int(redis("TTL", code_key(phone)))
    check(0 < ttl <= 300, f"unexpected registration code TTL: {ttl}")
    return code


def registration_body(
    username: str,
    phone: str,
    code: str,
    run_id: str,
) -> dict[str, Any]:
    return {
        "username": username[:20],
        "password": "QaSms123",
        "nickname": f"SMS QA {username[-4:]}",
        "gender": "male",
        "phone": phone,
        "sms_code": code,
        "device_id": f"sms-registration-{run_id}-{username[-4:]}",
        "device_type": "qa",
        "device_name": "SMS Registration QA",
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", default="http://127.0.0.1:8080/api/v1")
    parser.add_argument(
        "--output-dir",
        default="artifacts/real-device-qa/local-docker-dual-device-20260717/registration-sms-api",
    )
    args = parser.parse_args()

    api = Api(args.base_url)
    run_id = str(int(time.time()))
    seed = int(run_id[-8:])
    phones = [f"19{(seed + offset) % 1_000_000_000:09d}" for offset in range(5)]
    results: list[dict[str, Any]] = []

    settings = api.request("GET", "/app/settings").get("data", {})
    check(settings.get("sms_bind_ready") is True, "local SMS registration is not ready")

    # IM-006: sending twice inside the cooldown must be rejected.
    send_code(api, phones[0])
    expect_error(
        lambda: api.request(
            "POST", "/auth/register/send-code", body={"phone": phones[0]}
        ),
        codes={429},
    )
    results.append(
        {
            "case_ids": ["IM-006"],
            "status": "PASS",
            "detail": "registration SMS endpoint enforces a per-phone cooldown",
        }
    )

    # IM-003: five bad attempts are rejected, then the code is revoked.
    actual_code = send_code(api, phones[1])
    wrong_code = "000000" if actual_code != "000000" else "111111"
    wrong_body = registration_body(
        f"smsbad{run_id[-8:]}", phones[1], wrong_code, run_id
    )
    for _ in range(5):
        expect_error(
            lambda: api.request("POST", "/auth/register", body=wrong_body),
            codes={400},
            message_fragment="验证码错误",
        )
    expect_error(
        lambda: api.request("POST", "/auth/register", body=wrong_body),
        codes={429},
        message_fragment="错误次数过多",
    )
    check(redis("GET", code_key(phones[1])) == "", "code remained after brute-force limit")
    results.append(
        {
            "case_ids": ["IM-003"],
            "status": "PASS",
            "detail": "wrong codes never create an account and repeated attempts revoke the code",
        }
    )

    # IM-004: deleting the local TTL key deterministically simulates expiry.
    expired_code = send_code(api, phones[2])
    redis("DEL", code_key(phones[2]))
    expired_body = registration_body(
        f"smsexp{run_id[-8:]}", phones[2], expired_code, run_id
    )
    expect_error(
        lambda: api.request("POST", "/auth/register", body=expired_body),
        codes={400},
        message_fragment="验证码已失效",
    )
    results.append(
        {
            "case_ids": ["IM-004"],
            "status": "PASS",
            "detail": "expired registration codes are rejected without creating an account",
        }
    )

    # IM-001 and IM-005: register once, verify auto-login, then reject reuse.
    valid_code = send_code(api, phones[3])
    username = f"smsok{run_id[-10:]}"[:20]
    valid_body = registration_body(username, phones[3], valid_code, run_id)
    registered = api.request("POST", "/auth/register", body=valid_body).get("data", {})
    token = str(registered.get("token", ""))
    user = registered.get("user", {})
    check(token != "" and isinstance(user, dict), "registration did not return login state")
    check(user.get("phone") == phones[3], "registered phone was not persisted")
    check(redis("GET", code_key(phones[3])) == "", "used code was not consumed")
    me = api.request("GET", "/user/me", token=token).get("data", {})
    check(me.get("phone") == phones[3], "auto-login token cannot read bound phone")
    login = api.request(
        "POST",
        "/auth/login",
        body={
            "username": username,
            "password": "QaSms123",
            "device_id": f"sms-login-{run_id}",
            "device_type": "qa",
            "device_name": "SMS Login QA",
        },
    ).get("data", {})
    check(str(login.get("token", "")) != "", "new phone-registered account cannot log in")
    results.append(
        {
            "case_ids": ["IM-001"],
            "status": "PASS",
            "detail": "phone, SMS code and password create an account and return a valid login token",
        }
    )

    reuse_body = registration_body(
        f"smsreuse{run_id[-8:]}", phones[3], valid_code, run_id
    )
    expect_error(
        lambda: api.request("POST", "/auth/register", body=reuse_body),
        codes={400},
        message_fragment="验证码已失效",
    )
    results.append(
        {
            "case_ids": ["IM-005"],
            "status": "PASS",
            "detail": "a consumed registration code cannot be reused",
        }
    )

    output_dir = Path(args.output_dir).resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    output = output_dir / f"registration-sms-{run_id}.json"
    report = {
        "status": "PASS",
        "run_id": run_id,
        "base_url": args.base_url,
        "sms_delivery": "local debug console provider; no external SMS request",
        "results": results,
        "tested_at": datetime.now().astimezone().isoformat(timespec="seconds"),
    }
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
