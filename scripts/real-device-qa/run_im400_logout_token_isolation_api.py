#!/usr/bin/env python3
"""Validate logout push isolation and revoked-token behavior on local Docker."""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import time
import urllib.error
import urllib.request
import uuid
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


def docker_exec(container: str, command: list[str], *, env: dict[str, str] | None = None) -> str:
    args = ["docker", "exec"]
    for key, value in (env or {}).items():
        args.extend(["-e", f"{key}={value}"])
    args.extend([container, *command])
    completed = subprocess.run(
        args,
        text=True,
        encoding="utf-8",
        errors="replace",
        capture_output=True,
        timeout=30,
        check=False,
    )
    if completed.returncode != 0:
        raise RuntimeError(
            f"docker exec {container} failed: {completed.stderr.strip()}"
        )
    return completed.stdout.strip()


def redis(*args: str) -> str:
    return docker_exec("genericim-redis", ["redis-cli", "--raw", *args])


def mysql(sql: str) -> str:
    command = 'mysql -N -B -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" -e "$QA_SQL"'
    return docker_exec(
        "genericim-mysql",
        ["sh", "-lc", command],
        env={"QA_SQL": sql},
    )


def read_code(key: str) -> str:
    raw = redis("GET", key)
    try:
        decoded = json.loads(raw)
        code = decoded if isinstance(decoded, str) else raw
    except json.JSONDecodeError:
        code = raw
    check(len(code) == 6 and code.isdigit(), f"verification code missing for {key}")
    return code


def create_account(
    api: Api, username: str, phone: str, password: str, device_id: str
) -> dict[str, Any]:
    api.request("POST", "/auth/register/send-code", body={"phone": phone})
    code = read_code(f"auth:register:sms:{phone}")
    payload = api.request(
        "POST",
        "/auth/register",
        body={
            "username": username,
            "password": password,
            "nickname": f"Round12 {username[-4:]}",
            "gender": "male",
            "phone": phone,
            "sms_code": code,
            "device_id": device_id,
            "device_type": "qa",
            "device_name": "Round 12 registration",
        },
    ).get("data", {})
    check(str(payload.get("token", "")), "registration did not issue a token")
    check(isinstance(payload.get("user"), dict), "registration omitted user data")
    return payload


def login(
    api: Api, username: str, password: str, device_id: str, device_name: str
) -> str:
    payload = api.request(
        "POST",
        "/auth/login",
        body={
            "username": username,
            "password": password,
            "device_id": device_id,
            "device_type": "android",
            "device_name": device_name,
        },
    ).get("data", {})
    token = str(payload.get("token", ""))
    check(token != "", f"login for {device_id} did not issue a token")
    return token


def bind_push(
    api: Api, token: str, device_id: str, channel: str, push_token: str
) -> None:
    api.request(
        "POST",
        "/user/push-token",
        token=token,
        body={
            "device_id": device_id,
            "push_token": push_token,
            "device_type": "android",
            "push_channel": channel,
            "brand": "HUAWEI",
            "model": "Round12-QA",
            "device_name": "Round 12 push isolation",
            "app_version": "round12",
        },
    )


def assert_unauthorized(api: Api, path: str, token: str, action: str) -> None:
    status, payload = api.raw("POST" if path == "/auth/refresh" else "GET", path, token=token)
    check(
        status == 401 and payload.get("code") == 401,
        f"{action} was not rejected with 401: HTTP {status} {payload}",
    )


def delete_account(api: Api, token: str, user_uuid: str) -> None:
    api.request("POST", "/user/account/send-delete-code", token=token)
    key = f"verify:delete_account:{user_uuid}"
    code = read_code(key)
    api.request("DELETE", f"/user/account?code={code}", token=token)
    check(redis("GET", key) == "", "delete-account code was not consumed")


def token_state_count(user_id: int, device_prefix: str, predicate: str) -> int:
    sql = (
        "SELECT COUNT(*) FROM user_devices "
        f"WHERE user_id={user_id} AND "
        f"(device_id='{device_prefix}' OR device_id='{device_prefix}:voip' "
        f"OR device_id LIKE '{device_prefix}:push:%') AND ({predicate})"
    )
    return int(mysql(sql) or "0")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", default="http://127.0.0.1:8080/api/v1")
    parser.add_argument(
        "--output-dir",
        default="artifacts/real-device-qa/im400-round12-logout-token-isolation",
    )
    args = parser.parse_args()

    api = Api(args.base_url)
    run_id = f"{int(time.time())}{uuid.uuid4().hex[:4]}"
    numeric_seed = int("".join(character for character in run_id if character.isdigit())[-9:])
    phones = [f"18{(numeric_seed + index) % 1_000_000_000:09d}" for index in range(2)]
    username = f"r12a{run_id[-12:]}"[:20]
    other_username = f"r12b{run_id[-12:]}"[:20]
    password = "QaRound12Pass"
    device_a = f"round12-a-{run_id}"
    device_b = f"round12-b-{run_id}"
    device_other = f"round12-other-{run_id}"
    cleanup: list[tuple[str, str]] = []
    results: list[dict[str, Any]] = []

    try:
        registered = create_account(
            api, username, phones[0], password, f"round12-register-a-{run_id}"
        )
        user = registered["user"]
        user_id = int(user["id"])
        user_uuid = str(user["uuid"])
        cleanup.append((str(registered["token"]), user_uuid))

        other = create_account(
            api,
            other_username,
            phones[1],
            password,
            f"round12-register-b-{run_id}",
        )
        other_user = other["user"]
        other_id = int(other_user["id"])
        other_uuid = str(other_user["uuid"])
        cleanup.append((str(other["token"]), other_uuid))

        token_a = login(api, username, password, device_a, "Round 12 device A")
        token_b = login(api, username, password, device_b, "Round 12 device B")
        token_other = login(
            api, other_username, password, device_other, "Round 12 other user"
        )
        cleanup[0] = (token_b, user_uuid)
        cleanup[1] = (token_other, other_uuid)

        token_a_fcm = f"round12-fcm-{uuid.uuid4().hex}"
        token_a_hms = f"round12-hms-{uuid.uuid4().hex}"
        token_a_apns = uuid.uuid4().hex + uuid.uuid4().hex
        token_b_fcm = f"round12-b-fcm-{uuid.uuid4().hex}"
        token_other_hms = f"round12-other-hms-{uuid.uuid4().hex}"
        bind_push(api, token_a, device_a, "fcm", token_a_fcm)
        bind_push(api, token_a, device_a, "hms", token_a_hms)
        bind_push(api, token_a, device_a, "apns", token_a_apns)
        bind_push(api, token_b, device_b, "fcm", token_b_fcm)
        bind_push(api, token_other, device_other, "hms", token_other_hms)

        check(
            token_state_count(user_id, device_a, "push_token <> ''") == 3,
            "device A did not have all three push bindings before logout",
        )

        logout = api.request("POST", "/auth/logout", token=token_a).get("data", {})
        check(logout.get("logged_out") is True, "empty-body logout did not succeed")
        check(logout.get("bindings") == [], "empty-body logout returned unexpected bindings")

        residual = token_state_count(
            user_id,
            device_a,
            "push_token <> '' OR push_token_hash IS NOT NULL OR push_token_updated_at IS NOT NULL",
        )
        check(residual == 0, f"device A retained {residual} push-token fields")
        check(
            mysql(
                "SELECT push_token FROM user_devices "
                f"WHERE user_id={user_id} AND device_id='{device_b}:push:fcm'"
            )
            == token_b_fcm,
            "logout cleared the same user's device B binding",
        )
        check(
            mysql(
                "SELECT push_token FROM user_devices "
                f"WHERE user_id={other_id} AND device_id='{device_other}:push:hms'"
            )
            == token_other_hms,
            "logout cleared another user's binding",
        )
        assert_unauthorized(api, "/user/me", token_a, "logged-out token API access")
        assert_unauthorized(api, "/auth/refresh", token_a, "logged-out token refresh")
        api.request("GET", "/user/me", token=token_b)
        api.request("GET", "/user/me", token=token_other)
        results.append(
            {
                "case_id": "IM-013",
                "status": "PASS",
                "detail": (
                    "empty-body logout cleared APNs, FCM and HMS bindings for only "
                    "the JWT device; same-user device B and another user remained intact"
                ),
            }
        )

        token_revoke = login(api, username, password, device_a, "Round 12 revoke A")
        token_hash = hashlib.sha256(token_revoke.encode("utf-8")).hexdigest()
        revoked_key = f"user:token_revoked:{user_uuid}:{token_hash}"
        redis("SET", revoked_key, "true", "EX", "604800")
        check(redis("EXISTS", revoked_key) == "1", "revoked-token key was not stored")
        assert_unauthorized(api, "/user/me", token_revoke, "explicitly revoked token API access")
        assert_unauthorized(api, "/auth/refresh", token_revoke, "explicitly revoked token refresh")
        api.request("GET", "/user/me", token=token_b)

        replacement = login(api, username, password, device_a, "Round 12 replacement A")
        check(replacement != token_revoke, "fresh login reused the revoked token")
        api.request("GET", "/user/me", token=replacement)
        results.append(
            {
                "case_id": "IM-018",
                "status": "PASS",
                "detail": (
                    "a SHA-256-scoped Redis revocation blocked protected API and refresh "
                    "without affecting device B; fresh authentication restored access"
                ),
            }
        )

        output_dir = Path(args.output_dir).resolve()
        output_dir.mkdir(parents=True, exist_ok=True)
        output = output_dir / f"logout-token-isolation-{run_id}.json"
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
    finally:
        for token, user_uuid in cleanup:
            try:
                delete_account(api, token, user_uuid)
            except Exception as error:  # noqa: BLE001 - preserve primary QA failure
                print(f"cleanup warning for {user_uuid}: {error}")


if __name__ == "__main__":
    raise SystemExit(main())
