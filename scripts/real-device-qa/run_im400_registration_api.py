#!/usr/bin/env python3
"""Verify registration input-security contracts against a current-source API.

This runner does not send a real SMS and never prints or persists access tokens.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
import uuid
from pathlib import Path
from typing import Any

from run_im400_remaining_api import Api, ApiError, check, response_data


def expect_business_code(
    api: Api,
    method: str,
    path: str,
    *,
    body: dict[str, Any],
    code: int,
) -> dict[str, Any]:
    try:
        payload = api.request(method, path, body=body)
    except ApiError as error:
        payload = error.payload if isinstance(error.payload, dict) else {}
        check(
            int(payload.get("code", -1)) == code,
            f"{method} {path} returned unexpected error: {error}",
        )
        return payload
    raise AssertionError(
        f"{method} {path} unexpectedly succeeded; expected business code {code}: {payload}"
    )


def register_body(username: str) -> dict[str, Any]:
    return {
        "username": username,
        "password": f"Qa{uuid.uuid4().hex[:12]}",
        "nickname": "Registration contract QA",
        "gender": "male",
        "device_id": f"registration-contract-{uuid.uuid4().hex}",
        "device_type": "qa",
        "device_name": "Registration contract runner",
    }


def unique_username(prefix: str) -> str:
    return f"qa_{prefix}_{uuid.uuid4().hex[:10]}"[:20]


def redis_command(container: str, *arguments: str) -> str:
    completed = subprocess.run(
        ["docker", "exec", container, "redis-cli", "--raw", *arguments],
        check=True,
        capture_output=True,
        text=True,
    )
    return completed.stdout.strip()


def seed_registration_code(container: str, phone: str, code: str, ttl: int) -> None:
    result = redis_command(
        container,
        "SET",
        f"auth:register:sms:{phone}",
        json.dumps(code),
        "EX",
        str(ttl),
    )
    check(result == "OK", f"failed to seed registration code for {phone}: {result}")


def registration_body_with_phone(
    username: str, phone: str, code: str
) -> dict[str, Any]:
    body = register_body(username)
    body.update({"phone": phone, "sms_code": code})
    return body


def run_lifecycle_contracts(
    api: Api,
    redis_container: str,
    run_id: str,
    results: list[dict[str, Any]],
) -> None:
    suffix = str(int(time.time() * 1000))[-8:]
    brute_phone = f"139{suffix}"
    success_phone = f"158{str(int(suffix) + 1).zfill(8)[-8:]}"
    expired_phone = f"176{str(int(suffix) + 2).zfill(8)[-8:]}"
    code = "246810"
    cleanup_keys = [
        f"auth:register:sms:{phone}"
        for phone in (brute_phone, success_phone, expired_phone)
    ] + [
        f"rate:verify:attempt:register-phone:{phone}"
        for phone in (brute_phone, success_phone, expired_phone)
    ]

    redis_command(redis_container, "DEL", *cleanup_keys)
    try:
        seed_registration_code(redis_container, brute_phone, code, 300)
        brute_body = registration_body_with_phone(
            unique_username("m_brute"), brute_phone, "000000"
        )
        for _ in range(5):
            expect_business_code(
                api, "POST", "/auth/register", body=brute_body, code=400
            )
        expect_business_code(
            api, "POST", "/auth/register", body=brute_body, code=429
        )
        check(
            redis_command(
                redis_container, "EXISTS", f"auth:register:sms:{brute_phone}"
            )
            == "0",
            "registration code remained usable after the attempt limit",
        )
        results.append(
            {
                "case": "wrong_code_attempt_limit",
                "status": "PASS",
                "detail": "five wrong attempts were rejected; the sixth returned 429 and revoked the code",
            }
        )

        seed_registration_code(redis_container, success_phone, code, 300)
        success_username = unique_username("m_success")
        success_payload = api.request(
            "POST",
            "/auth/register",
            body=registration_body_with_phone(
                success_username, success_phone, code
            ),
        )
        success_data = response_data(success_payload)
        check(
            isinstance(success_data, dict)
            and isinstance(success_data.get("user"), dict)
            and success_data["user"].get("phone") == success_phone,
            f"successful phone registration returned invalid data: {success_payload}",
        )
        check(
            redis_command(
                redis_container, "EXISTS", f"auth:register:sms:{success_phone}"
            )
            == "0",
            "successful registration did not consume the code",
        )
        replay_body = registration_body_with_phone(
            unique_username("m_replay"), success_phone, code
        )
        expect_business_code(
            api, "POST", "/auth/register", body=replay_body, code=400
        )
        seed_registration_code(redis_container, success_phone, code, 300)
        expect_business_code(
            api, "POST", "/auth/register", body=replay_body, code=409
        )
        results.append(
            {
                "case": "consume_replay_and_unique_phone",
                "status": "PASS",
                "detail": "success consumed the code; replay was rejected and a newly verified duplicate phone returned 409",
            }
        )

        seed_registration_code(redis_container, expired_phone, code, 1)
        time.sleep(1.2)
        expired_body = registration_body_with_phone(
            unique_username("m_expired"), expired_phone, code
        )
        expect_business_code(
            api, "POST", "/auth/register", body=expired_body, code=400
        )
        results.append(
            {
                "case": "expired_code",
                "status": "PASS",
                "detail": "an expired registration code was rejected and created no account",
            }
        )
    finally:
        redis_command(redis_container, "DEL", *cleanup_keys)


def run(
    base_url: str, output_dir: Path, redis_container: str | None = None
) -> dict[str, Any]:
    api = Api(base_url.rstrip("/") + "/api/v1")
    run_id = f"{int(time.time())}-{uuid.uuid4().hex[:6]}"
    results: list[dict[str, Any]] = []

    send_code_error = expect_business_code(
        api,
        "POST",
        "/auth/register/send-code",
        body={"phone": "12000000000"},
        code=400,
    )
    results.append(
        {
            "case": "invalid_prefix_send_code",
            "status": "PASS",
            "detail": "invalid mainland prefix rejected before SMS gateway readiness check",
            "business_code": send_code_error.get("code"),
        }
    )

    if redis_container:
        run_lifecycle_contracts(api, redis_container, run_id, results)

    invalid_phone_username = unique_username("l_badphone")
    invalid_phone = register_body(invalid_phone_username)
    invalid_phone.update({"phone": "12000000000", "sms_code": "123456"})
    phone_error = expect_business_code(
        api, "POST", "/auth/register", body=invalid_phone, code=400
    )
    results.append(
        {
            "case": "invalid_prefix_register",
            "status": "PASS",
            "detail": "registration rejected an invalid mobile prefix before code lookup",
            "business_code": phone_error.get("code"),
        }
    )

    invalid_code_username = unique_username("l_badcode")
    invalid_code = register_body(invalid_code_username)
    invalid_code.update({"phone": "13800138000", "sms_code": "ABC123"})
    code_error = expect_business_code(
        api, "POST", "/auth/register", body=invalid_code, code=400
    )
    results.append(
        {
            "case": "non_digit_sms_code",
            "status": "PASS",
            "detail": "six-character alphanumeric text was rejected as an SMS code",
            "business_code": code_error.get("code"),
        }
    )

    optional_username = unique_username("l_optional")
    optional_payload = api.request(
        "POST", "/auth/register", body=register_body(optional_username)
    )
    optional_data = response_data(optional_payload)
    check(
        isinstance(optional_data, dict)
        and isinstance(optional_data.get("user"), dict)
        and bool(optional_data["user"].get("uuid")),
        f"phone-optional registration did not return a user: {optional_payload}",
    )
    results.append(
        {
            "case": "phone_optional_registration",
            "status": "PASS",
            "detail": "registration without phone credentials remained available",
        }
    )

    report = {
        "run_id": run_id,
        "base_url": base_url,
        "results": results,
        "summary": {"passed": len(results), "failed": 0},
    }
    output_dir.mkdir(parents=True, exist_ok=True)
    report_path = output_dir / f"registration-api-{run_id}.json"
    report_path.write_text(
        json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    report["report_path"] = str(report_path)
    return report


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", default="http://127.0.0.1:8080")
    parser.add_argument("--output-dir", required=True)
    parser.add_argument(
        "--redis-container",
        help="optional local Redis container used to seed synthetic lifecycle codes",
    )
    args = parser.parse_args()
    try:
        report = run(
            args.base_url,
            Path(args.output_dir).resolve(),
            args.redis_container,
        )
    except Exception as error:  # noqa: BLE001
        print(
            json.dumps(
                {"status": "FAIL", "error": str(error)},
                ensure_ascii=False,
                indent=2,
            )
        )
        return 1
    print(json.dumps({"status": "PASS", **report}, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
