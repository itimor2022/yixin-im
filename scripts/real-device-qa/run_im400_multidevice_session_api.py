#!/usr/bin/env python3
"""Validate multi-device coexistence, forced logout, and re-login locally."""

from __future__ import annotations

import argparse
import json
import subprocess
import time
import urllib.error
import urllib.parse
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


def login_body(username: str, password: str, device_id: str, device_name: str) -> dict[str, str]:
    return {
        "username": username,
        "password": password,
        "device_id": device_id,
        "device_type": "android",
        "device_name": device_name,
    }


def delete_account(api: Api, token: str, user_uuid: str) -> None:
    api.request("POST", "/user/account/send-delete-code", token=token)
    code = read_code(f"verify:delete_account:{user_uuid}")
    api.request("DELETE", f"/user/account?code={code}", token=token)


def cleanup_stale_accounts(api: Api, current_username: str, password: str) -> None:
    rows = mysql("SELECT username FROM users WHERE username LIKE 'multqa%'")
    for username in (line.strip() for line in rows.splitlines()):
        if not username or username == current_username:
            continue
        try:
            data = api.request(
                "POST",
                "/auth/login",
                body=login_body(
                    username,
                    password,
                    f"multqa-cleanup-{int(time.time())}",
                    "Multi-device QA Cleanup",
                ),
            ).get("data", {})
            token = str(data.get("token", ""))
            user_uuid = str(data.get("user", {}).get("uuid", ""))
            if token and user_uuid:
                delete_account(api, token, user_uuid)
        except Exception as error:  # noqa: BLE001
            print(f"stale cleanup warning for {username}: {error}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", default="http://127.0.0.1:8080/api/v1")
    parser.add_argument(
        "--output-dir",
        default="artifacts/real-device-qa/local-docker-dual-device-20260717/multidevice-session-api",
    )
    args = parser.parse_args()

    api = Api(args.base_url)
    run_id = str(int(time.time()))
    username = f"multqa{run_id[-10:]}"[:20]
    password = "QaMultiDevice123"
    phone = f"16{int(run_id[-8:]) % 1_000_000_000:09d}"
    device_a = f"im021-device-a-{run_id}"
    device_b = f"im021-device-b-{run_id}"
    token_a = ""
    token_b = ""
    cleanup_token = ""
    user_uuid = ""
    results: list[dict[str, Any]] = []

    try:
        code = f"{int(run_id) % 1_000_000:06d}"
        redis("SETEX", f"auth:register:sms:{phone}", "300", json.dumps(code))
        registered = api.request(
            "POST",
            "/auth/register",
            body={
                "username": username,
                "password": password,
                "nickname": f"Multi Device {run_id[-4:]}",
                "gender": "male",
                "phone": phone,
                "sms_code": code,
                "device_id": device_a,
                "device_type": "android",
                "device_name": "IM021 Device A",
            },
        ).get("data", {})
        token_a = str(registered.get("token", ""))
        user_uuid = str(registered.get("user", {}).get("uuid", ""))
        check(token_a and user_uuid, "registration did not create device A session")

        login_b = api.request(
            "POST",
            "/auth/login",
            body=login_body(username, password, device_b, "IM021 Device B"),
        ).get("data", {})
        token_b = str(login_b.get("token", ""))
        cleanup_token = token_b
        check(login_b.get("multi_device_policy") == "coexist", "coexist policy missing")
        check(
            int(login_b.get("other_active_device_count", 0)) == 1,
            f"unexpected other device count: {login_b}",
        )

        devices = api.request("GET", "/user/devices", token=token_b).get("data", {})
        device_rows = devices.get("devices", [])
        active_ids = {
            str(row.get("device_id", ""))
            for row in device_rows
            if row.get("has_active_session") is True
        }
        check({device_a, device_b}.issubset(active_ids), f"device list mismatch: {device_rows}")
        results.append(
            {
                "case_ids": ["IM-021"],
                "status": "PASS",
                "detail": "device B login reported coexist policy and exactly one other active device; both active devices appeared in the authoritative device list",
            }
        )

        encoded_a = urllib.parse.quote(device_a, safe="")
        api.request("DELETE", f"/user/devices/{encoded_a}", token=token_b)
        status, payload = api.raw("GET", "/user/me", token=token_a)
        check(
            status >= 400 or payload.get("code") != 0,
            "terminated device A token remained usable",
        )
        api.request("GET", "/user/me", token=token_b)
        results.append(
            {
                "case_ids": ["IM-025"],
                "status": "PASS",
                "detail": "device B terminated device A; A's token was rejected immediately while B remained authenticated",
            }
        )

        login_a_again = api.request(
            "POST",
            "/auth/login",
            body=login_body(username, password, device_a, "IM021 Device A"),
        ).get("data", {})
        cleanup_token = str(login_a_again.get("token", ""))
        check(cleanup_token, "device A did not receive a new token")
        check(
            login_a_again.get("multi_device_policy") == "coexist"
            and int(login_a_again.get("other_active_device_count", 0)) == 1,
            f"re-login context mismatch: {login_a_again}",
        )
        api.request("GET", "/user/me", token=cleanup_token)
        results.append(
            {
                "case_ids": ["IM-026"],
                "status": "PASS",
                "detail": "the terminated device logged in again with a fresh token and no stale-session or blank-page API state",
            }
        )
    finally:
        if cleanup_token and user_uuid:
            try:
                delete_account(api, cleanup_token, user_uuid)
            except Exception as error:  # noqa: BLE001
                print(f"cleanup warning: {error}")
        cleanup_stale_accounts(api, username, password)

    output_dir = Path(args.output_dir).resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    output = output_dir / f"multidevice-session-{run_id}.json"
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
