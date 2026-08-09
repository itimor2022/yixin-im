#!/usr/bin/env python3
"""Validate local email registration without contacting an external provider."""

from __future__ import annotations

import argparse
import json
import subprocess
import time
import urllib.error
import urllib.request
from datetime import datetime
from pathlib import Path
from typing import Any, Callable


class ApiError(RuntimeError):
    def __init__(self, method: str, path: str, status: int, payload: dict[str, Any]):
        super().__init__(f"{method} {path} returned HTTP {status}: {payload}")
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
        payload = json.loads(raw) if raw else {}
        if status >= 400 or payload.get("code") != 0:
            raise ApiError(method, path, status, payload)
        return payload


def check(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def expect_error(action: Callable[[], Any], codes: set[int]) -> ApiError:
    try:
        action()
    except ApiError as error:
        business_code = int(error.payload.get("code", error.status))
        check(business_code in codes, f"unexpected error response: {error.payload}")
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


def code_key(email: str) -> str:
    return f"auth:register:email:{email.lower()}"


def read_code(email: str) -> str:
    raw = redis("GET", code_key(email))
    try:
        decoded = json.loads(raw)
        code = decoded if isinstance(decoded, str) else raw
    except json.JSONDecodeError:
        code = raw
    check(len(code) == 6 and code.isdigit(), "email code was not stored in local Redis")
    return code


def send_code(api: Api, email: str) -> str:
    response = api.request(
        "POST", "/auth/register/send-email-code", body={"email": email}
    )
    code = read_code(email)
    check(code not in json.dumps(response), "email code leaked through the API response")
    ttl = int(redis("TTL", code_key(email)))
    check(0 < ttl <= 300, f"unexpected email code TTL: {ttl}")
    return code


def registration_body(
    username: str, email: str, code: str, run_id: str
) -> dict[str, Any]:
    return {
        "username": username[:20],
        "password": "QaEmail123",
        "nickname": f"Email QA {username[-4:]}",
        "gender": "female",
        "email": email,
        "email_code": code,
        "device_id": f"email-registration-{run_id}-{username[-4:]}",
        "device_type": "qa",
        "device_name": "Email Registration QA",
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", default="http://127.0.0.1:8080/api/v1")
    parser.add_argument(
        "--output-dir",
        default="artifacts/real-device-qa/local-docker-dual-device-20260717/registration-email-api",
    )
    args = parser.parse_args()

    api = Api(args.base_url)
    run_id = str(int(time.time()))
    emails = [f"im400.email.{run_id}.{index}@example.test" for index in range(5)]
    checks: list[str] = []

    settings = api.request("GET", "/app/settings").get("data", {})
    check(settings.get("email_registration_ready") is True, "email registration is not ready")

    expect_error(
        lambda: api.request(
            "POST", "/auth/register/send-email-code", body={"email": "invalid"}
        ),
        {400},
    )
    checks.append("invalid email addresses are rejected")

    send_code(api, emails[0])
    expect_error(
        lambda: api.request(
            "POST", "/auth/register/send-email-code", body={"email": emails[0]}
        ),
        {429},
    )
    checks.append("per-address send cooldown is enforced")

    actual_code = send_code(api, emails[1])
    wrong_code = "000000" if actual_code != "000000" else "111111"
    wrong_body = registration_body(f"emailbad{run_id[-8:]}", emails[1], wrong_code, run_id)
    for _ in range(5):
        expect_error(lambda: api.request("POST", "/auth/register", body=wrong_body), {400})
    expect_error(lambda: api.request("POST", "/auth/register", body=wrong_body), {429})
    check(redis("GET", code_key(emails[1])) == "", "email code survived brute-force limit")
    checks.append("five bad attempts revoke the email code")

    expired_code = send_code(api, emails[2])
    redis("DEL", code_key(emails[2]))
    expired_body = registration_body(
        f"emailexp{run_id[-8:]}", emails[2], expired_code, run_id
    )
    expect_error(lambda: api.request("POST", "/auth/register", body=expired_body), {400})
    checks.append("expired email codes are rejected")

    valid_code = send_code(api, emails[3])
    username = f"emailok{run_id[-9:]}"[:20]
    valid_body = registration_body(username, emails[3], valid_code, run_id)
    registered = api.request("POST", "/auth/register", body=valid_body).get("data", {})
    token = str(registered.get("token", ""))
    user = registered.get("user", {})
    check(token and isinstance(user, dict), "registration did not return login state")
    check(user.get("email") == emails[3], "registered email was not persisted")
    check(redis("GET", code_key(emails[3])) == "", "used email code was not consumed")

    me = api.request("GET", "/user/me", token=token).get("data", {})
    check(me.get("email") == emails[3], "authenticated profile omitted the email")
    login = api.request(
        "POST",
        "/auth/login",
        body={
            "username": username,
            "password": "QaEmail123",
            "device_id": f"email-login-{run_id}",
            "device_type": "qa",
            "device_name": "Email Login QA",
        },
    ).get("data", {})
    check(str(login.get("token", "")), "email-registered account cannot log in")
    checks.append("email code registration persists the email and creates a login session")

    reuse_body = registration_body(
        f"emailreuse{run_id[-7:]}", emails[3], valid_code, run_id
    )
    expect_error(lambda: api.request("POST", "/auth/register", body=reuse_body), {400})
    expect_error(
        lambda: api.request(
            "POST", "/auth/register/send-email-code", body={"email": emails[3]}
        ),
        {409},
    )
    checks.append("consumed codes cannot be reused and registered emails stay unique")

    output_dir = Path(args.output_dir).resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    output = output_dir / f"registration-email-{run_id}.json"
    report = {
        "status": "PASS",
        "case_ids": ["IM-002"],
        "base_url": args.base_url,
        "delivery": "local debug console provider; no external email request",
        "detail": "email verification registration, login, expiry, replay, brute-force and rate-limit checks passed",
        "checks": checks,
        "tested_at": datetime.now().astimezone().isoformat(timespec="seconds"),
    }
    output.write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
