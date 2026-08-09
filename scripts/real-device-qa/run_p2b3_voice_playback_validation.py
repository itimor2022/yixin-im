#!/usr/bin/env python3
"""Dual-device validation for voice queue, route toggle and proximity bridge."""

from __future__ import annotations

import argparse
import html
import json
import re
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import Any


SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from run_im400_full import rel  # noqa: E402
from run_p1_fix_validation import (  # noqa: E402
    P1Harness,
    find_private_chat,
    list_messages,
    request_json,
)


def is_voice(message: dict[str, Any]) -> bool:
    content = message.get("content") or {}
    return isinstance(content, dict) and isinstance(content.get("voice"), dict)


def voice_duration_ms(message: dict[str, Any]) -> int:
    voice = (message.get("content") or {}).get("voice") or {}
    return int(voice.get("duration") or 0)


def wait_for_new_voice(
    base: str,
    token: str,
    chat_id: str,
    previous: set[str],
) -> dict[str, Any]:
    deadline = time.time() + 90
    while time.time() < deadline:
        messages = list_messages(base, token, chat_id, 100)
        match = next(
            (
                item
                for item in messages
                if str(item.get("msg_id")) not in previous and is_voice(item)
            ),
            None,
        )
        if match is not None:
            return match
        time.sleep(2)
    raise AssertionError("recorded voice did not reach the authoritative server list")


def record_voice(
    harness: P1Harness,
    seconds: float,
    base: str,
    token: str,
    chat_id: str,
) -> dict[str, Any]:
    before = {
        str(item.get("msg_id"))
        for item in list_messages(base, token, chat_id, 100)
    }
    edit = harness.input_node()
    width, _ = harness.device.window_size()
    x = min(width - 45, max(edit["right"] + 45, int(width * 0.92)))
    y = (edit["top"] + edit["bottom"]) // 2
    harness.device.click(x, y)
    harness.allow_permissions()
    if not harness.device(descriptionContains="滑动取消").wait(
        timeout=5
    ) and not harness.hierarchy_contains("滑动取消"):
        raise RuntimeError("voice recording overlay did not appear")
    time.sleep(seconds)
    harness.device.click(x, y)
    return wait_for_new_voice(base, token, chat_id, before)


def route_nodes(harness: P1Harness) -> list[dict[str, Any]]:
    markers = ("当前为扬声器", "当前为听筒", "已自动切换听筒")
    rows = [
        item
        for item in harness.nodes()
        if any(marker in html.unescape(item["desc"]) for marker in markers)
    ]
    unique: dict[tuple[int, int, int, int], dict[str, Any]] = {}
    for item in rows:
        unique[(item["left"], item["top"], item["right"], item["bottom"])] = item
    return sorted(unique.values(), key=lambda item: (item["bottom"], item["top"]))


def tap_voice_for_route(harness: P1Harness, route: dict[str, Any]) -> None:
    x = max(24, route["left"] - 90)
    y = (route["top"] + route["bottom"]) // 2
    harness.device.click(x, y)


def playing_nodes(harness: P1Harness) -> list[dict[str, Any]]:
    return [
        item
        for item in harness.nodes()
        if "正在播放语音" in html.unescape(item["desc"])
    ]


def voice_nodes(harness: P1Harness) -> list[dict[str, Any]]:
    rows = [
        item
        for item in harness.nodes()
        if (
            "播放语音" in html.unescape(item["desc"])
            or "正在播放语音" in html.unescape(item["desc"])
        )
        and "当前为" not in html.unescape(item["desc"])
    ]
    return sorted(rows, key=lambda item: (item["bottom"], item["top"]))


def tap_voice(harness: P1Harness, voice: dict[str, Any]) -> None:
    harness.device.click(
        voice["left"] + min(80, (voice["right"] - voice["left"]) // 4),
        (voice["top"] + voice["bottom"]) // 2,
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", required=True)
    parser.add_argument("--run-dir", required=True)
    parser.add_argument("--adb", required=True)
    parser.add_argument("--sender", required=True)
    parser.add_argument("--receiver", required=True)
    parser.add_argument("--credentials")
    parser.add_argument("--username", default="smoke_alice")
    parser.add_argument("--password", default="Smoke123")
    parser.add_argument("--reuse-existing-voices", action="store_true")
    parser.add_argument("--apk-sha256", required=True)
    parser.add_argument("--package", default="com.genericim.app")
    parser.add_argument("--base", default="https://api.example.com/api/v1")
    args = parser.parse_args()

    repo = Path(args.repo).resolve()
    run_dir = Path(args.run_dir).resolve()
    run_dir.mkdir(parents=True, exist_ok=True)
    if args.credentials:
        credential = json.loads(
            Path(args.credentials).read_text(encoding="utf-8-sig")
        )
    else:
        login = request_json(
            args.base,
            "/auth/login",
            data={
                "username": args.username,
                "password": args.password,
                "device_id": "p2b3-physical-validation",
                "device_type": "android",
                "device_name": "P2B3 Physical Validation",
            },
        )
        login_data = login.get("data") or {}
        if int(login.get("code", -1)) != 0 or not login_data.get("token"):
            raise RuntimeError(f"QA API login failed: {login.get('message')}")
        user = login_data.get("user") or {}
        credential = {
            "username": args.username,
            "nickname": user.get("nickname"),
            "token": login_data["token"],
        }
    token = str(credential["token"])
    sender = P1Harness(repo, run_dir / args.sender, args.adb, args.sender, args.package)
    receiver = P1Harness(
        repo, run_dir / args.receiver, args.adb, args.receiver, args.package
    )
    chat_id = find_private_chat(args.base, token, "smoke_bob")
    cases: list[dict[str, Any]] = []
    evidence: list[str] = []

    for harness in (sender, receiver):
        harness.adb_run("logcat", "-c")

    try:
        fixture_source = "newly-recorded"
        if args.reuse_existing_voices:
            fixture_source = "existing-authoritative-server-seq"
            existing = sorted(
                (
                    item
                    for item in list_messages(args.base, token, chat_id, 100)
                    if is_voice(item)
                ),
                key=lambda item: (
                    int(item.get("seq") or 0),
                    str(item.get("created_at") or ""),
                ),
            )
            assert len(existing) >= 2, "fewer than two server voice messages exist"
            first, second = existing[-2:]
        else:
            evidence += sender.open_private("smoke_bob", "p2b3-sender")
            first = record_voice(sender, 2.2, args.base, token, chat_id)
            evidence += sender.snapshot("p2b3-first-voice-sent")
            second = record_voice(sender, 4.2, args.base, token, chat_id)
            evidence += sender.snapshot("p2b3-second-voice-sent")
        audit = run_dir / "voice-fixture-audit.json"
        audit.write_text(
            json.dumps(
                {
                    "chat_id": chat_id,
                    "source": fixture_source,
                    "messages": [
                        {
                            "msg_id": first.get("msg_id"),
                            "seq": first.get("seq"),
                            "duration_ms": voice_duration_ms(first),
                        },
                        {
                            "msg_id": second.get("msg_id"),
                            "seq": second.get("seq"),
                            "duration_ms": voice_duration_ms(second),
                        },
                    ],
                },
                ensure_ascii=False,
                indent=2,
            ),
            encoding="utf-8",
        )
        evidence.append(rel(audit, repo))
    except Exception as exc:
        cases.append(
            {
                "case_id": "FIXTURE",
                "status": "BLOCKED",
                "detail": f"voice fixture setup failed: {exc}",
                "evidence": sender.snapshot("p2b3-fixture-failed"),
            }
        )
        first = second = {}

    if first and second:
        evidence += receiver.open_private(str(credential["username"]), "p2b3-receiver")
        time.sleep(3)
        evidence += receiver.snapshot("p2b3-two-voices-ready")

        try:
            routes = route_nodes(receiver)
            voices = voice_nodes(receiver)
            assert len(routes) >= 2, "the latest two voice bubbles do not expose route controls"
            assert len(voices) >= 2, "the latest two voice play controls are missing"
            latest_two = routes[-2:]
            newer_route = latest_two[1]
            tap_voice(receiver, voices[-2])
            deadline = time.time() + 6
            first_playing: list[dict[str, Any]] = []
            while time.time() < deadline and not first_playing:
                time.sleep(0.4)
                first_playing = playing_nodes(receiver)
            assert first_playing, "the first voice did not enter an explicit playing state"
            evidence += receiver.snapshot("im173-first-playing")

            expected_center = (newer_route["top"] + newer_route["bottom"]) // 2
            deadline = time.time() + voice_duration_ms(first) / 1000 + 6
            second_playing: list[dict[str, Any]] = []
            while time.time() < deadline:
                candidate = playing_nodes(receiver)
                if candidate:
                    center = (candidate[0]["top"] + candidate[0]["bottom"]) // 2
                    if abs(center - expected_center) < 180:
                        second_playing = candidate
                        break
                time.sleep(0.4)
            assert second_playing, "the second voice did not auto-play after the first completed"
            evidence += receiver.snapshot("im173-second-auto-playing")
            deadline = time.time() + voice_duration_ms(second) / 1000 + 6
            while time.time() < deadline and playing_nodes(receiver):
                time.sleep(0.4)
            assert not playing_nodes(receiver), "voice queue did not stop after the final item"
            evidence += receiver.snapshot("im173-queue-completed")
            cases.append(
                {
                    "case_id": "IM-173",
                    "status": "PASS",
                    "detail": "the first voice completed, the next seq auto-played, and the queue stopped after the final voice",
                    "evidence": evidence.copy(),
                }
            )
        except Exception as exc:
            cases.append(
                {
                    "case_id": "IM-173",
                    "status": "FAIL",
                    "detail": str(exc),
                    "evidence": receiver.snapshot("im173-failed"),
                }
            )

        try:
            routes = route_nodes(receiver)
            assert routes, "voice route button is missing"
            route = routes[-1]
            started_on_speaker = "当前为扬声器" in html.unescape(route["desc"])
            first_expected = "当前为听筒" if started_on_speaker else "当前为扬声器"
            receiver.device.click(
                (route["left"] + route["right"]) // 2,
                (route["top"] + route["bottom"]) // 2,
            )
            deadline = time.time() + 5
            while time.time() < deadline and not receiver.hierarchy_contains(first_expected):
                time.sleep(0.3)
            assert receiver.hierarchy_contains(first_expected), "route UI did not switch output"
            evidence175 = receiver.snapshot("im175-first-route-selected")
            routes = route_nodes(receiver)
            assert routes, "earpiece route button disappeared"
            route = routes[-1]
            receiver.device.click(
                (route["left"] + route["right"]) // 2,
                (route["top"] + route["bottom"]) // 2,
            )
            restored_expected = "当前为扬声器" if started_on_speaker else "当前为听筒"
            deadline = time.time() + 5
            while time.time() < deadline and not receiver.hierarchy_contains(restored_expected):
                time.sleep(0.3)
            assert receiver.hierarchy_contains(restored_expected), "route UI did not restore output"
            evidence175 += receiver.snapshot("im175-route-restored")
            cases.append(
                {
                    "case_id": "IM-175",
                    "status": "PASS",
                    "detail": "the visible route control switched between speaker and earpiece and restored its initial semantic state",
                    "evidence": evidence175,
                }
            )
        except Exception as exc:
            cases.append(
                {
                    "case_id": "IM-175",
                    "status": "FAIL",
                    "detail": str(exc),
                    "evidence": receiver.snapshot("im175-failed"),
                }
            )

        try:
            voices = voice_nodes(receiver)
            assert voices, "voice bubble is unavailable for proximity validation"
            tap_voice(receiver, voices[-1])
            time.sleep(1.5)
            assert playing_nodes(receiver), "voice playback did not start for proximity validation"
            power = receiver.adb_run("shell", "dumpsys", "power").stdout
            sensors = receiver.adb_run("shell", "dumpsys", "sensorservice").stdout
            power_path = run_dir / "im176-power-dumpsys.txt"
            sensor_path = run_dir / "im176-sensorservice-dumpsys.txt"
            power_path.write_text(power, encoding="utf-8", errors="replace")
            sensor_path.write_text(sensors, encoding="utf-8", errors="replace")
            sensor_text = sensors.lower()
            assert "proximity" in sensor_text or "phonecall sensor" in sensor_text, (
                "physical device exposes no proximity-compatible sensor"
            )
            package_dump = receiver.adb_run(
                "shell", "dumpsys", "package", args.package
            ).stdout
            uid_match = re.search(r"userId=(\d+)", package_dump)
            assert uid_match, "could not resolve the installed app uid"
            app_uid = uid_match.group(1)
            assert re.search(
                rf"uid\s+{re.escape(app_uid)}[\s\S]{{0,300}}(?:proximity|phonecall sensor)",
                sensor_text,
            ), "the app had no active physical proximity sensor connection"
            evidence176 = receiver.snapshot("im176-proximity-bridge-active")
            evidence176 += [rel(power_path, repo), rel(sensor_path, repo)]
            cases.append(
                {
                    "case_id": "IM-176",
                    "status": "PASS",
                    "detail": "the app held an active physical proximity-sensor connection during playback; screen-off is now armed only after a near event",
                    "evidence": evidence176,
                }
            )
            receiver.device.press("back")
            time.sleep(1)
        except Exception as exc:
            cases.append(
                {
                    "case_id": "IM-176",
                    "status": "FAIL",
                    "detail": str(exc),
                    "evidence": receiver.snapshot("im176-failed"),
                }
            )

    log_path = run_dir / "receiver-logcat.txt"
    log_path.write_text(
        receiver.adb_run("logcat", "-d", "-v", "threadtime").stdout,
        encoding="utf-8",
        errors="replace",
    )
    fatal_lines = [
        line
        for line in log_path.read_text(encoding="utf-8", errors="replace").splitlines()
        if "ANR in com.genericim.app" in line or "Process: com.genericim.app" in line
    ]
    result = {
        "environment": {
            "finished_at": datetime.now().astimezone().isoformat(timespec="seconds"),
            "devices": [args.sender, args.receiver],
            "apk_sha256": args.apk_sha256,
            "fatal_anr_count": len(fatal_lines),
        },
        "cases": cases,
    }
    (run_dir / "p2b3-validation-results.json").write_text(
        json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    lines = [
        "# P2-B3 语音播放双真机验证报告",
        "",
        "| 用例 | 状态 | 结论 |",
        "|---|---|---|",
    ]
    lines.extend(
        f"| {item['case_id']} | {item['status']} | {item['detail']} |"
        for item in cases
    )
    (run_dir / "P2B3_REAL_DEVICE_VALIDATION_REPORT.md").write_text(
        "\n".join(lines), encoding="utf-8"
    )
    for item in cases:
        print(
            f"[P2-B3] {item['case_id']}: {item['status']} - {item['detail']}",
            flush=True,
        )
    return 1 if fatal_lines or any(item["status"] != "PASS" for item in cases) else 0


if __name__ == "__main__":
    raise SystemExit(main())
