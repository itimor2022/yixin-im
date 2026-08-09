#!/usr/bin/env python3
"""Focused physical-device validation for IM-162/163/179/186."""

from __future__ import annotations

import argparse
import json
import re
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import Any, Callable


SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from run_im400_full import rel  # noqa: E402
from run_p1_fix_validation import P1Harness, find_private_chat, list_messages  # noqa: E402


def write_report(run_dir: Path, environment: dict[str, Any], cases: list[dict[str, Any]]) -> None:
    payload = {"environment": environment, "cases": cases}
    (run_dir / "p2b1-validation-results.json").write_text(
        json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    counts = {
        status: sum(item["status"] == status for item in cases)
        for status in ("PASS", "FAIL", "BLOCKED")
    }
    lines = [
        "# P2-B1 媒体修复真机验证报告",
        "",
        f"- 完成时间：{environment['finished_at']}",
        f"- 设备：{environment['device']}",
        f"- APK SHA256：`{environment['apk_sha256']}`",
        f"- 结果：PASS {counts['PASS']} / FAIL {counts['FAIL']} / BLOCKED {counts['BLOCKED']}",
        "",
        "| 用例 | 状态 | 结论 |",
        "|---|---|---|",
    ]
    for item in cases:
        lines.append(f"| {item['case_id']} | {item['status']} | {item['detail']} |")
    lines += ["", "## 证据", ""]
    for item in cases:
        lines += [f"### {item['case_id']} {item['status']}", ""]
        lines.extend(f"- `{path}`" for path in item["evidence"])
        lines.append("")
    (run_dir / "P2B1_REAL_DEVICE_VALIDATION_REPORT.md").write_text(
        "\n".join(lines), encoding="utf-8"
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", required=True)
    parser.add_argument("--run-dir", required=True)
    parser.add_argument("--adb", required=True)
    parser.add_argument("--device", required=True)
    parser.add_argument("--credentials", required=True)
    parser.add_argument("--apk-sha256", required=True)
    parser.add_argument("--peer", default="smoke_bob")
    parser.add_argument(
        "--case",
        action="append",
        choices=["IM-162", "IM-163", "IM-179", "IM-186"],
    )
    parser.add_argument("--package", default="com.genericim.app")
    parser.add_argument("--base", default="https://api.example.com/api/v1")
    args = parser.parse_args()

    repo = Path(args.repo).resolve()
    run_dir = Path(args.run_dir).resolve()
    run_dir.mkdir(parents=True, exist_ok=True)
    credential = json.loads(Path(args.credentials).read_text(encoding="utf-8-sig"))
    token = str(credential["token"])
    harness = P1Harness(repo, run_dir / args.device, args.adb, args.device, args.package)
    chat_id = find_private_chat(args.base, token, args.peer)
    cases: list[dict[str, Any]] = []
    selected = set(args.case or ["IM-162", "IM-163", "IM-179", "IM-186"])
    harness.adb_run("logcat", "-c")

    def record(case_id: str, body: Callable[[], tuple[str, list[str]]]) -> None:
        if case_id not in selected:
            return
        try:
            detail, evidence = body()
            status = "PASS"
        except AssertionError as exc:
            status, detail = "FAIL", str(exc)
            evidence = harness.snapshot(f"{case_id.lower()}-failed")
        except Exception as exc:
            status = "BLOCKED"
            detail = f"自动化前置异常：{type(exc).__name__}: {exc}"
            evidence = harness.snapshot(f"{case_id.lower()}-blocked")
        cases.append(
            {"case_id": case_id, "status": status, "detail": detail, "evidence": evidence}
        )
        print(f"[P2-B1] {case_id}: {status} - {detail}", flush=True)

    def im162() -> tuple[str, list[str]]:
        evidence = harness.open_private("smoke_bob", "im162")
        before_ids = {
            str(item.get("msg_id")) for item in list_messages(args.base, token, chat_id, 100)
        }
        edit = harness.input_node()
        width, _ = harness.device.window_size()
        x = min(width - 45, max(edit["right"] + 45, int(width * 0.92)))
        y = (edit["top"] + edit["bottom"]) // 2
        harness.device.click(x, y)
        time.sleep(0.35)
        harness.device.click(x, y)
        time.sleep(0.35)
        evidence += harness.snapshot("im162-short-recording-warning")
        assert harness.hierarchy_contains("录音时间太短"), "短录音停止后没有明确提示"
        time.sleep(2)
        after_ids = {
            str(item.get("msg_id")) for item in list_messages(args.base, token, chat_id, 100)
        }
        assert after_ids == before_ids, "不足 1 秒的录音被错误发送"
        return "不足 1 秒录音不发送，并显示“录音时间太短”提示。", evidence

    def im179() -> tuple[str, list[str]]:
        evidence = harness.open_private("smoke_bob", "im179")
        time.sleep(2)
        evidence += harness.snapshot("im179-transcription-hidden")
        assert not harness.hierarchy_contains("转文字"), "服务未配置时仍显示转文字入口"
        return "线上服务未配置语音识别能力时，语音气泡不再显示“转文字”。", evidence

    def im186() -> tuple[str, list[str]]:
        evidence = harness.open_private(args.peer, "im186")
        candidate: dict[str, Any] | None = None
        for _ in range(14):
            candidates = [
                item
                for item in harness.nodes()
                if item["class"] == "android.widget.ImageView"
                and item["clickable"]
                and re.search(r"\b\d+(?:\.\d+)?\s*(?:KB|MB|GB)\b", item["desc"])
            ]
            if candidates:
                candidate = max(candidates, key=lambda item: item["bottom"])
                break
            width, height = harness.device.window_size()
            harness.device.swipe(width // 2, int(height * 0.42), width // 2, int(height * 0.82), 0.35)
            time.sleep(0.8)
        if candidate is None:
            raise RuntimeError("chat video bubble not found")

        # A playable video message must expose its server-generated poster in
        # the chat bubble before the player route is opened. Capture this
        # state separately so a successful player test cannot hide a missing
        # thumbnail regression.
        evidence += harness.snapshot("im186-video-cover")
        assert candidate["right"] - candidate["left"] >= 150, (
            "video cover bubble is too small to be a rendered poster"
        )
        assert candidate["bottom"] - candidate["top"] >= 120, (
            "video cover bubble has no usable poster height"
        )
        harness.device.click(
            (candidate["left"] + candidate["right"]) // 2,
            (candidate["top"] + candidate["bottom"]) // 2,
        )
        time.sleep(6)
        assert not harness.device(className="android.widget.EditText").exists(timeout=1), "视频播放页未打开"
        portrait_size = harness.device.screenshot().size
        evidence += harness.snapshot("im186-video-portrait")

        original_auto = harness.adb_run(
            "shell", "settings", "get", "system", "accelerometer_rotation"
        ).stdout.strip()
        original_rotation = harness.adb_run(
            "shell", "settings", "get", "system", "user_rotation"
        ).stdout.strip()
        try:
            harness.adb_run("shell", "settings", "put", "system", "accelerometer_rotation", "0")
            harness.adb_run("shell", "settings", "put", "system", "user_rotation", "1")
            deadline = time.time() + 10
            landscape_size = portrait_size
            while time.time() < deadline:
                landscape_size = harness.device.screenshot().size
                if landscape_size[0] > landscape_size[1]:
                    break
                time.sleep(0.7)
            evidence += harness.snapshot("im186-video-landscape")
            assert landscape_size[0] > landscape_size[1], (
                f"强制横屏后截图尺寸仍为 {landscape_size[0]}x{landscape_size[1]}"
            )
        finally:
            harness.adb_run(
                "shell", "settings", "put", "system", "accelerometer_rotation", original_auto or "1"
            )
            harness.adb_run(
                "shell", "settings", "put", "system", "user_rotation", original_rotation or "0"
            )
        harness.device.press("back")
        time.sleep(3)
        evidence += harness.snapshot("im186-exit-restored-portrait")
        restored_size = harness.device.screenshot().size
        assert restored_size[1] > restored_size[0], "退出播放器后没有恢复竖屏"
        return "视频播放页可横屏显示，退出后恢复竖屏且返回原会话。", evidence

    def im163() -> tuple[str, list[str]]:
        evidence = harness.open_private("smoke_bob", "im163")
        before_ids = {
            str(item.get("msg_id")) for item in list_messages(args.base, token, chat_id, 100)
        }
        harness.start_voice()
        evidence += harness.snapshot("im163-recording-started")
        started = time.monotonic()
        deadline = started + 315
        while time.monotonic() < deadline and harness.hierarchy_contains("滑动取消"):
            time.sleep(0.8)
        elapsed = time.monotonic() - started
        evidence += harness.snapshot("im163-auto-stopped")
        assert elapsed >= 295, f"录音在 {elapsed:.1f} 秒提前结束"
        assert not harness.hierarchy_contains("滑动取消"), "达到 300 秒后录音覆盖层仍未关闭"

        after_ids = before_ids
        upload_deadline = time.time() + 90
        while time.time() < upload_deadline:
            after_ids = {
                str(item.get("msg_id")) for item in list_messages(args.base, token, chat_id, 100)
            }
            if after_ids - before_ids:
                break
            time.sleep(3)
        evidence += harness.snapshot("im163-five-minute-voice-sent")
        assert after_ids - before_ids, "300 秒自动停录后语音没有发送到服务端"
        return "录音达到 300 秒后自动结束、关闭录音层并发送 5 分钟语音。", evidence

    record("IM-162", im162)
    record("IM-179", im179)
    record("IM-186", im186)
    record("IM-163", im163)

    log_path = run_dir / f"{args.device}-logcat.txt"
    log_path.write_text(
        harness.adb_run("logcat", "-d", "-v", "threadtime").stdout,
        encoding="utf-8",
    )
    log_text = log_path.read_text(encoding="utf-8", errors="replace")
    fatal_lines = [
        line
        for line in log_text.splitlines()
        if "ANR in com.genericim.app" in line or "Process: com.genericim.app" in line
    ]
    fatal_path = run_dir / "fatal-anr-audit.json"
    fatal_path.write_text(
        json.dumps({"count": len(fatal_lines), "lines": fatal_lines}, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    environment = {
        "finished_at": datetime.now().astimezone().isoformat(timespec="seconds"),
        "device": args.device,
        "apk_sha256": args.apk_sha256,
        "fatal_anr_count": len(fatal_lines),
    }
    write_report(run_dir, environment, cases)
    return 1 if any(item["status"] != "PASS" for item in cases) or fatal_lines else 0


if __name__ == "__main__":
    raise SystemExit(main())
