#!/usr/bin/env python3
"""Validate account presence aggregation across a real app and a second WS session."""

from __future__ import annotations

import argparse
import json
import subprocess
import time
import urllib.parse
from datetime import datetime
from pathlib import Path
from typing import Any

import uiautomator2 as u2

from run_im400_presence_real_device import adb, login, snapshot, wait_online
from run_im400_remaining_api import Api, check


def start_ws_probe(
    dart: str,
    script: Path,
    base_url: str,
    token: str,
) -> subprocess.Popen[str]:
    http_url = urllib.parse.urlparse(base_url)
    scheme = "wss" if http_url.scheme == "https" else "ws"
    query = urllib.parse.urlencode({"device_type": "qa", "token": token})
    url = f"{scheme}://{http_url.netloc}/api/v1/ws?{query}"
    process = subprocess.Popen(
        [dart, "run", str(script), url],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        encoding="utf-8",
        errors="replace",
        cwd=script.parents[2],
    )
    deadline = time.monotonic() + 20
    while time.monotonic() < deadline:
        line = process.stdout.readline().strip() if process.stdout else ""
        if line == "CONNECTED":
            return process
        if process.poll() is not None:
            stderr = process.stderr.read() if process.stderr else ""
            raise RuntimeError(f"WS probe exited before connect: {stderr}")
    process.terminate()
    raise RuntimeError("WS probe connection timed out")


def stop_ws_probe(process: subprocess.Popen[str]) -> None:
    if process.poll() is not None:
        return
    if process.stdin:
        process.stdin.write("STOP\n")
        process.stdin.flush()
    try:
        process.wait(timeout=10)
    except subprocess.TimeoutExpired:
        process.terminate()
        process.wait(timeout=5)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", default="http://127.0.0.1:8080")
    parser.add_argument("--adb", required=True)
    parser.add_argument("--dart", required=True)
    parser.add_argument("--viewer-device", required=True)
    parser.add_argument("--target-device", required=True)
    parser.add_argument("--viewer-username", default="smoke_alice")
    parser.add_argument("--target-username", default="smoke_bob")
    parser.add_argument("--password", default="Smoke123")
    parser.add_argument("--package", default="com.genericim.ma100")
    parser.add_argument("--output-dir", required=True)
    args = parser.parse_args()

    output_dir = Path(args.output_dir).resolve() / datetime.now().strftime(
        "%Y%m%d-%H%M%S"
    )
    output_dir.mkdir(parents=True, exist_ok=True)
    repo = Path(__file__).resolve().parents[2]
    api = Api(args.base_url.rstrip("/") + "/api/v1")
    viewer = login(api, args.viewer_username, args.password, f"im038-viewer-{int(time.time())}")
    target_probe = login(api, args.target_username, args.password, f"im038-probe-{int(time.time())}")
    viewer_device = u2.connect(args.viewer_device)
    target_device = u2.connect(args.target_device)
    evidence: list[str] = []
    fatal_lines: dict[str, list[str]] = {}
    error = ""
    checks: dict[str, Any] = {}
    probe: subprocess.Popen[str] | None = None

    for serial in (args.viewer_device, args.target_device):
        adb(args.adb, serial, "logcat", "-c")

    try:
        viewer_device.app_start(args.package, stop=False, wait=True)
        target_device.app_start(args.package, stop=False, wait=True)
        wait_online(api, viewer, target_probe.user_id, True, 20)
        evidence += snapshot(target_device, output_dir, "01-real-device-online")

        probe = start_ws_probe(
            args.dart,
            repo / "scripts" / "real-device-qa" / "hold_ws_session.dart",
            args.base_url,
            target_probe.token,
        )
        time.sleep(2)
        with_probe = wait_online(api, viewer, target_probe.user_id, True, 10)

        target_device.app_stop(args.package)
        probe_only = wait_online(api, viewer, target_probe.user_id, True, 15)

        target_device.app_start(args.package, stop=False, wait=True)
        wait_online(api, viewer, target_probe.user_id, True, 20)
        stop_ws_probe(probe)
        probe = None
        real_only = wait_online(api, viewer, target_probe.user_id, True, 15)
        evidence += snapshot(target_device, output_dir, "02-real-device-only-online")

        target_device.app_stop(args.package)
        both_offline = wait_online(api, viewer, target_probe.user_id, False, 20)
        checks = {
            "both_connections_online": with_probe,
            "probe_only_still_online": probe_only,
            "real_device_only_still_online": real_only,
            "both_disconnected_offline": both_offline,
        }
    except Exception as exc:
        error = f"{type(exc).__name__}: {exc}"
        evidence += snapshot(viewer_device, output_dir, "test-failed-viewer")
        evidence += snapshot(target_device, output_dir, "test-failed-target")
    finally:
        if probe is not None:
            stop_ws_probe(probe)
        target_device.app_start(args.package, stop=False, wait=True)

    for serial in (args.viewer_device, args.target_device):
        log = adb(args.adb, serial, "logcat", "-d", "-v", "threadtime")
        (output_dir / f"logcat-{serial}.txt").write_text(log, encoding="utf-8")
        fatal_lines[serial] = [
            line
            for line in log.splitlines()
            if "FATAL EXCEPTION" in line
            or "ANR in com.genericim.ma100" in line
            or "FlutterError" in line
        ]

    status = "PASS" if not error and not any(fatal_lines.values()) else "FAIL"
    payload = {
        "status": status,
        "case_id": "IM-038",
        "cases": {
            "IM-038": {
                "status": status,
                "detail": error
                or "account presence stayed online while either the real device or the second WebSocket device remained connected, and changed offline only after both disconnected",
            }
        },
        "checks": checks,
        "evidence": evidence,
        "fatal_lines": fatal_lines,
        "fatal_anr_flutter_error_zero": not any(fatal_lines.values()),
        "result_path": str((output_dir / "case-result.json").resolve()),
    }
    (output_dir / "case-result.json").write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(
        json.dumps(
            {"status": status, "case_id": "IM-038", "result_path": payload["result_path"]},
            ensure_ascii=False,
        )
    )
    return 0 if status == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
