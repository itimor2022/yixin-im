#!/usr/bin/env python3
"""Validate disposable-account deletion and banned-login contracts locally."""

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


class Api:
    def __init__(self, base_url: str):
        self.base_url = base_url.rstrip("/")

    def raw(
        self,
        method: str,
        path: str,
        *,
        body: dict[str, Any] | None = None,
        token: str | None = None,
    ) -> tuple[int, dict[str, Any]]:
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
            with urllib.request.urlopen(request, timeout=90) as response:
                status = response.status
                raw = response.read().decode("utf-8")
        except urllib.error.HTTPError as error:
            status = error.code
            raw = error.read().decode("utf-8", errors="replace")
        return status, json.loads(raw) if raw else {}

    def request(self, method: str, path: str, **kwargs: Any) -> dict[str, Any]:
        status, payload = self.raw(method, path, **kwargs)
        if status >= 400 or payload.get("code") != 0:
            raise AssertionError(f"{method} {path} failed: HTTP {status} {payload}")
        return payload


def check(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


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


def mysql(sql: str) -> str:
    command = 'mysql -N -B -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" -e "$QA_SQL"'
    completed = subprocess.run(
        ["docker", "exec", "-e", f"QA_SQL={sql}", "genericim-mysql", "sh", "-lc", command],
        text=True,
        encoding="utf-8",
        errors="replace",
        capture_output=True,
        timeout=30,
        check=False,
    )
    if completed.returncode != 0:
        raise RuntimeError(f"mysql failed: {completed.stderr.strip()}")
    return completed.stdout.strip()


def read_code(key: str) -> str:
    raw = redis("GET", key)
    try:
        decoded = json.loads(raw)
        code = decoded if isinstance(decoded, str) else raw
    except json.JSONDecodeError:
        code = raw
    check(len(code) == 6 and code.isdigit(), f"verification code missing for {key}")
    return code


def create_phone_account(
    api: Api, username: str, phone: str, run_id: str
) -> dict[str, Any]:
    api.request("POST", "/auth/register/send-code", body={"phone": phone})
    code = read_code(f"auth:register:sms:{phone}")
    data = api.request(
        "POST",
        "/auth/register",
        body={
            "username": username,
            "password": "QaLifecycle123",
            "nickname": f"Lifecycle {username[-4:]}",
            "gender": "male",
            "phone": phone,
            "sms_code": code,
            "device_id": f"lifecycle-{run_id}-{username[-4:]}",
            "device_type": "qa",
            "device_name": "Account Lifecycle QA",
        },
    ).get("data", {})
    check(str(data.get("token", "")), "registration did not issue a token")
    check(isinstance(data.get("user"), dict), "registration omitted user data")
    return data


def delete_account(api: Api, token: str, user_uuid: str) -> None:
    api.request("POST", "/user/account/send-delete-code", token=token)
    key = f"verify:delete_account:{user_uuid}"
    code = read_code(key)
    response = api.request("DELETE", f"/user/account?code={code}", token=token)
    check(response.get("code") == 0, "account deletion did not succeed")
    check(redis("GET", key) == "", "delete-account code was not consumed")


def login_payload(username: str, run_id: str) -> dict[str, Any]:
    return {
        "username": username,
        "password": "QaLifecycle123",
        "device_id": f"lifecycle-login-{run_id}",
        "device_type": "qa",
        "device_name": "Lifecycle Login QA",
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", default="http://127.0.0.1:8080/api/v1")
    parser.add_argument(
        "--output-dir",
        default="artifacts/real-device-qa/local-docker-dual-device-20260717/account-lifecycle-api",
    )
    args = parser.parse_args()

    api = Api(args.base_url)
    run_id = str(int(time.time()))
    seed = int(run_id[-8:])
    phones = [f"18{(seed + index) % 1_000_000_000:09d}" for index in range(4)]
    results: list[dict[str, Any]] = []

    deleted_username = f"delqa{run_id[-10:]}"[:20]
    original = create_phone_account(api, deleted_username, phones[0], run_id)
    original_user = original["user"]
    original_uuid = str(original_user.get("uuid", ""))
    delete_account(api, str(original["token"]), original_uuid)

    status, payload = api.raw("POST", "/auth/login", body=login_payload(deleted_username, run_id))
    check(payload.get("code") != 0, "deleted account unexpectedly logged in")
    status, payload = api.raw("GET", "/user/me", token=str(original["token"]))
    check(status >= 400 or payload.get("code") != 0, "deleted account token remained usable")
    results.append(
        {
            "case_ids": ["IM-014", "IM-016"],
            "status": "PASS",
            "detail": "SMS identity verification physically deleted a disposable account; old credentials and token were rejected",
        }
    )

    recreated = create_phone_account(api, deleted_username, phones[1], run_id)
    recreated_uuid = str(recreated["user"].get("uuid", ""))
    check(recreated_uuid and recreated_uuid != original_uuid, "re-registration restored the old identity")
    delete_account(api, str(recreated["token"]), recreated_uuid)

    banned_username = f"banqa{run_id[-10:]}"[:20]
    banned = create_phone_account(api, banned_username, phones[2], run_id)
    banned_user = banned["user"]
    banned_id = int(banned_user["id"])
    banned_uuid = str(banned_user["uuid"])
    reason = "IM-017 local QA policy violation"
    mysql(
        "UPDATE users SET status=3, ban_reason='IM-017 local QA policy violation', "
        f"banned_at=NOW(), updated_at=NOW() WHERE id={banned_id} LIMIT 1"
    )
    check(mysql(f"SELECT status FROM users WHERE id={banned_id}") == "3", "ban state was not applied")

    _, payload = api.raw("POST", "/auth/login", body=login_payload(banned_username, run_id))
    check(payload.get("code") == 1008, f"banned login returned the wrong code: {payload}")
    data = payload.get("data", {})
    check(reason in str(payload.get("message", "")), "ban reason missing from login response")
    check(data.get("ban_until") == "until_unbanned", "ban duration metadata missing")
    check(data.get("appeal_action") == "contact_support", "appeal action missing")
    check(not data.get("token"), "banned login unexpectedly issued a token")
    results.append(
        {
            "case_ids": ["IM-017"],
            "status": "PASS",
            "detail": "banned credentials were blocked with reason, permanent-until-unbanned duration and contact-support appeal metadata",
        }
    )

    delete_account(api, str(banned["token"]), banned_uuid)

    output_dir = Path(args.output_dir).resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    output = output_dir / f"account-lifecycle-{run_id}.json"
    report = {
        "status": "PASS",
        "base_url": args.base_url,
        "results": results,
        "tested_at": datetime.now().astimezone().isoformat(timespec="seconds"),
    }
    output.write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
