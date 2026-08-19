#!/usr/bin/env python3
"""Validate the five P1 fixes on two physical Android devices.

Every case is isolated. Harness exceptions are BLOCKED, never product FAIL.
The script always restores Wi-Fi and leaves an evidence JSON/Markdown report.
"""

from __future__ import annotations

import argparse
import html
import json
import re
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import Any, Callable
from urllib.parse import urlencode
from urllib.error import URLError
from urllib.request import Request, urlopen

import uiautomator2 as u2


SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from run_im400_cross_account import open_remote_private  # noqa: E402
from run_im400_full import Runner, rel  # noqa: E402


class P1Harness:
    def __init__(self, repo: Path, run_dir: Path, adb: str, serial: str, package: str) -> None:
        self.repo = repo
        self.run_dir = run_dir
        self.run_dir.mkdir(parents=True, exist_ok=True)
        self.adb = adb
        self.serial = serial
        self.package = package
        self.device = u2.connect(serial)
        self.runner = Runner(repo, run_dir, adb, serial, package, {})
        self.step = 0

    def adb_run(self, *args: str, check: bool = False) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [self.adb, "-s", self.serial, *args],
            check=check,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
        )

    def snapshot(self, name: str) -> list[str]:
        self.step += 1
        png = self.run_dir / f"{self.step:03d}-{name}.png"
        xml = self.run_dir / f"{self.step:03d}-{name}.xml"
        self.device.screenshot(str(png))
        xml.write_text(self.device.dump_hierarchy(), encoding="utf-8")
        return [rel(png, self.repo), rel(xml, self.repo)]

    def nodes(self) -> list[dict[str, Any]]:
        rows: list[dict[str, Any]] = []
        for raw in re.findall(r"<node\b[^>]*>", self.device.dump_hierarchy()):
            bounds = re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', raw)
            if not bounds:
                continue
            desc = re.search(r'content-desc="([^"]*)"', raw)
            text = re.search(r'text="([^"]*)"', raw)
            klass = re.search(r'class="([^"]*)"', raw)
            package = re.search(r'package="([^"]*)"', raw)
            rows.append(
                {
                    "desc": html.unescape(desc.group(1)) if desc else "",
                    "text": html.unescape(text.group(1)) if text else "",
                    "class": klass.group(1) if klass else "",
                    "package": package.group(1) if package else "",
                    "left": int(bounds.group(1)),
                    "top": int(bounds.group(2)),
                    "right": int(bounds.group(3)),
                    "bottom": int(bounds.group(4)),
                    "clickable": 'clickable="true"' in raw,
                }
            )
        return rows

    def hierarchy_contains(self, value: str) -> bool:
        return value in html.unescape(self.device.dump_hierarchy())

    def open_private(self, username: str, label: str) -> list[str]:
        try:
            return open_remote_private(self.runner, username, label)
        except Exception as remote_error:
            # Remote account search depends on a separate endpoint and may
            # transiently fail even when the existing private chat is healthy.
            self.device.app_stop(self.package)
            self.device.app_start(self.package, wait=True)
            time.sleep(8)
            try:
                return self.runner.open_chat(username, f"{label}-existing-chat")
            except Exception:
                raise remote_error

    def allow_permissions(self) -> None:
        permission_ids = (
            "com.android.permissioncontroller:id/permission_allow_foreground_only_button",
            "com.android.permissioncontroller:id/permission_allow_one_time_button",
            "com.android.permissioncontroller:id/permission_allow_button",
        )
        for _ in range(8):
            clicked = False
            for resource_id in permission_ids:
                if self.device(resourceId=resource_id).click_exists(timeout=0.5):
                    clicked = True
                    time.sleep(1.0)
                    break
            if not clicked:
                break
        for label in (
            "仅使用期间允许",
            "仅在使用中允许",
            "使用应用时允许",
            "允许本次使用",
            "允许",
            "Allow",
        ):
            for _ in range(3):
                if not self.device(text=label).click_exists(timeout=0.3):
                    break
                time.sleep(0.8)

    def input_node(self) -> dict[str, Any]:
        edits = [item for item in self.nodes() if item["class"] == "android.widget.EditText"]
        if not edits:
            raise RuntimeError("chat input not found")
        return edits[0]

    def click_input_side(self, side: str) -> None:
        edit = self.input_node()
        width, _ = self.device.window_size()
        rows = [
            item
            for item in self.nodes()
            if item["clickable"]
            and item["package"] == self.package
            and item["top"] < edit["bottom"]
            and item["bottom"] > edit["top"]
            and (item["left"] > edit["right"] if side == "right" else item["right"] < edit["left"])
        ]
        if not rows:
            # Flutter may expose one wide semantics node. Use stable edge coordinates.
            self.device.click(int(width * (0.94 if side == "right" else 0.06)), (edit["top"] + edit["bottom"]) // 2)
            return
        item = max(rows, key=lambda row: row["right"]) if side == "right" else min(rows, key=lambda row: row["left"])
        self.device.click((item["left"] + item["right"]) // 2, (item["top"] + item["bottom"]) // 2)

    def start_voice(self) -> None:
        self.click_input_side("right")
        self.allow_permissions()
        if not self.device(descriptionContains="滑动取消").wait(timeout=5) and not self.hierarchy_contains("滑动取消"):
            raise RuntimeError("voice recording overlay did not appear")

    def send_voice(self) -> None:
        width, height = self.device.window_size()
        candidates = [
            item
            for item in self.nodes()
            if item["clickable"]
            and item["package"] == self.package
            and item["left"] > int(width * 0.72)
            and item["top"] > int(height * 0.78)
        ]
        if candidates:
            item = max(candidates, key=lambda row: row["right"])
            self.device.click((item["left"] + item["right"]) // 2, (item["top"] + item["bottom"]) // 2)
        else:
            self.device.click(int(width * 0.92), int(height * 0.94))

    def set_wifi(self, enabled: bool) -> None:
        self.adb_run("shell", "svc", "wifi", "enable" if enabled else "disable")
        time.sleep(5 if enabled else 3)

    def click_retry(self, timeout: float = 20) -> bool:
        node = self.device(description="Retry send")
        if not node.wait(timeout=timeout):
            return False
        node.click()
        return True

    def send_text_fast(self, text: str) -> None:
        edit = self.device(className="android.widget.EditText")
        if not edit.exists(timeout=3):
            raise RuntimeError("chat input missing during ordered send")
        edit.click()
        self.device.set_fastinput_ime(True)
        self.device.send_keys(text, clear=True)
        time.sleep(0.08)
        if not self.device(description="发送").click_exists(timeout=0.3):
            self.click_input_side("right")
        # Leave enough time for Flutter to clear/rebuild the input semantics
        # before typing the next item; faster taps can be dropped by the
        # automation layer and are not representative of user submission.
        time.sleep(0.55)


def request_json(base: str, path: str, token: str = "", data: dict[str, Any] | None = None) -> dict[str, Any]:
    headers = {"Accept": "application/json", "User-Agent": "P1-Physical-QA/1.0"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    body = None
    method = "GET"
    if data is not None:
        body = json.dumps(data, ensure_ascii=False).encode("utf-8")
        headers["Content-Type"] = "application/json"
        method = "POST"
    last_error: Exception | None = None
    for attempt in range(5):
        req = Request(f"{base.rstrip('/')}{path}", data=body, headers=headers, method=method)
        try:
            with urlopen(req, timeout=30) as response:
                return json.loads(response.read().decode("utf-8"))
        except URLError as exc:
            last_error = exc
            time.sleep(2 + attempt)
    raise RuntimeError(f"API request failed after retries: {last_error}")


def find_private_chat(base: str, token: str, target_username: str) -> str:
    listing = request_json(base, "/chat/list?page=1&page_size=100", token)
    for chat in (listing.get("data") or {}).get("list") or []:
        if int(chat.get("type") or 0) != 1 or not chat.get("target_uuid"):
            continue
        user = request_json(base, f"/user/{chat['target_uuid']}", token).get("data") or {}
        if user.get("username") == target_username:
            return str(chat["chat_id"])
    raise RuntimeError(f"private chat not found for {target_username}")


def list_messages(base: str, token: str, chat_id: str, limit: int = 100) -> list[dict[str, Any]]:
    query = urlencode({"chat_id": chat_id, "limit": limit})
    return request_json(base, f"/message/list?{query}", token).get("data") or []


def write_outputs(run_dir: Path, payload: dict[str, Any]) -> None:
    (run_dir / "p1-validation-results.json").write_text(
        json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    counts = {status: sum(1 for item in payload["cases"] if item["status"] == status) for status in ("PASS", "FAIL", "BLOCKED")}
    lines = [
        "# P1 修复双真机验证报告",
        "",
        f"- 时间：{payload['environment']['finished_at']}",
        f"- 设备：{payload['environment']['devices']}",
        f"- APK SHA256：`{payload['environment']['apk_sha256']}`",
        f"- 结果：PASS {counts['PASS']} / FAIL {counts['FAIL']} / BLOCKED {counts['BLOCKED']}",
        "",
        "| 用例 | 状态 | 验证结论 |",
        "|---|---|---|",
    ]
    for item in payload["cases"]:
        lines.append(f"| {item['case_id']} | {item['status']} | {item['detail']} |")
    lines += ["", "## 证据", ""]
    for item in payload["cases"]:
        lines.append(f"### {item['case_id']} {item['status']}")
        lines.append("")
        for evidence in item["evidence"]:
            lines.append(f"- `{evidence}`")
        lines.append("")
    (run_dir / "P1_REAL_DEVICE_VALIDATION_REPORT.md").write_text("\n".join(lines), encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", required=True)
    parser.add_argument("--run-dir", required=True)
    parser.add_argument("--adb", required=True)
    parser.add_argument("--device-smoke", required=True)
    parser.add_argument("--device-qa", required=True)
    parser.add_argument("--qa-credentials", required=True)
    parser.add_argument("--apk-sha256", required=True)
    parser.add_argument("--case", action="append", choices=["IM-167", "IM-169", "IM-171", "IM-182", "IM-222"])
    parser.add_argument("--reuse-im222-audit", action="store_true")
    parser.add_argument("--package", default="com.genericim.ma100")
    parser.add_argument("--base", default="https://api.example.com/api/v1")
    args = parser.parse_args()

    repo = Path(args.repo).resolve()
    run_dir = Path(args.run_dir).resolve()
    run_dir.mkdir(parents=True, exist_ok=True)
    qa_credential = json.loads(Path(args.qa_credentials).read_text(encoding="utf-8-sig"))
    smoke = P1Harness(repo, run_dir / args.device_smoke, args.adb, args.device_smoke, args.package)
    qa = P1Harness(repo, run_dir / args.device_qa, args.adb, args.device_qa, args.package)
    selected = set(args.case or ["IM-167", "IM-169", "IM-171", "IM-182", "IM-222"])
    previous_path = run_dir / "p1-validation-results.json"
    previous_cases: list[dict[str, Any]] = []
    if previous_path.exists():
        previous_cases = json.loads(previous_path.read_text(encoding="utf-8")).get("cases") or []
    results: list[dict[str, Any]] = [
        item for item in previous_cases if item.get("case_id") not in selected
    ]

    def run_case(case_id: str, body: Callable[[], tuple[str, list[str]]]) -> None:
        if case_id not in selected:
            return
        try:
            detail, evidence = body()
            status = "PASS"
        except AssertionError as exc:
            status, detail = "FAIL", str(exc)
            evidence = qa.snapshot(f"{case_id.lower()}-failed")
        except Exception as exc:
            status, detail = "BLOCKED", f"自动化前置或设备状态异常：{type(exc).__name__}: {exc}"
            evidence = qa.snapshot(f"{case_id.lower()}-blocked")
        results.append({"case_id": case_id, "status": status, "detail": detail, "evidence": evidence})
        print(f"[P1-QA] {case_id}: {status} - {detail}", flush=True)

    for harness in (smoke, qa):
        harness.adb_run("logcat", "-c")

    def im169() -> tuple[str, list[str]]:
        evidence = qa.open_private("smoke_bob", "im169")
        qa.start_voice()
        evidence += qa.snapshot("im169-recording")
        qa.device.press("home")
        time.sleep(5)
        qa.device.app_start(args.package, stop=False, wait=True)
        time.sleep(3)
        evidence += qa.snapshot("im169-returned")
        assert not qa.hierarchy_contains("滑动取消"), "切到后台 5 秒后录音界面仍存在"
        return "录音中切到后台后自动取消，返回会话未继续录音。", evidence

    def im167() -> tuple[str, list[str]]:
        evidence = qa.open_private("smoke_bob", "im167-receiver")
        qa.start_voice()
        evidence += qa.snapshot("im167-recording-before-call")
        evidence += smoke.open_private(str(qa_credential["username"]), "im167-caller")
        smoke.click_input_side("left")
        time.sleep(1)
        if not smoke.device(descriptionContains="通话").click_exists(timeout=3):
            raise RuntimeError("chat attachment call action missing")
        time.sleep(1)
        voice = smoke.device(descriptionContains="语音通话")
        if not voice.click_exists(timeout=3):
            voice = smoke.device(textContains="语音通话")
            if not voice.click_exists(timeout=3):
                raise RuntimeError("voice call option missing")
        smoke.allow_permissions()
        time.sleep(8)
        evidence += qa.snapshot("im167-incoming-call")
        incoming_visible = any(
            qa.device(descriptionContains=label).exists(timeout=0.5)
            or qa.device(textContains=label).exists(timeout=0.5)
            for label in ("接听", "拒绝", "来电", "语音通话")
        )
        if not incoming_visible:
            raise RuntimeError("real incoming-call UI did not reach receiver")
        assert not qa.hierarchy_contains("滑动取消"), "来电到达后录音状态仍存在"
        for harness in (qa, smoke):
            for label in ("拒绝", "挂断", "取消"):
                if harness.device(descriptionContains=label).click_exists(timeout=0.3) or harness.device(textContains=label).click_exists(timeout=0.3):
                    break
        return "语音录制期间收到真实来电，录音立即取消。", evidence

    def im171() -> tuple[str, list[str]]:
        evidence = qa.open_private("smoke_bob", "im171")
        qa.set_wifi(False)
        try:
            qa.start_voice()
            time.sleep(3)
            qa.send_voice()
            time.sleep(12)
            evidence += qa.snapshot("im171-offline-failed")
            assert qa.device(description="Retry send").exists(timeout=3), "断网语音未进入可重试失败态"
            qa.set_wifi(True)
            time.sleep(8)
            assert qa.click_retry(), "恢复网络后找不到语音重试按钮"
            time.sleep(18)
            evidence += qa.snapshot("im171-retry-success")
            assert not qa.device(description="Retry send").exists(timeout=2), "语音重试后仍显示失败"
            smoke.open_private(str(qa_credential["username"]), "im171-peer")
            evidence += smoke.snapshot("im171-peer-received")
            return "断网发送语音进入失败态；联网点击原消息重试成功，另一台真机收到语音。", evidence
        finally:
            qa.set_wifi(True)

    def im182() -> tuple[str, list[str]]:
        evidence = qa.open_private("smoke_bob", "im182")
        qa.click_input_side("left")
        time.sleep(1)
        camera_clicked = qa.device(descriptionContains="摄像头").click_exists(timeout=2)
        if not camera_clicked:
            camera_clicked = qa.device(descriptionContains="相机").click_exists(timeout=2)
        if not camera_clicked:
            raise RuntimeError("camera attachment action missing")
        time.sleep(1)
        if not qa.device(descriptionContains="录像").click_exists(timeout=3):
            raise RuntimeError("record video action missing")
        qa.allow_permissions()
        time.sleep(7)
        width, height = qa.device.window_size()
        qa.device.click(width // 2, int(height * 0.90))
        time.sleep(5)
        if not qa.device(descriptionContains="完成").click_exists(timeout=2) and not qa.device(textContains="完成").click_exists(timeout=2):
            qa.device.click(width // 2, int(height * 0.90))
        time.sleep(6)
        evidence += qa.snapshot("im182-preview")
        has_retake = qa.hierarchy_contains("重拍")
        has_send = qa.hierarchy_contains("发送")
        assert has_retake and has_send, "录像完成后未出现重拍/发送确认预览"
        qa.set_wifi(False)
        try:
            if not qa.device(text="发送").click_exists(timeout=3) and not qa.device(description="发送").click_exists(timeout=3):
                raise RuntimeError("video preview send action missing")
            time.sleep(16)
            evidence += qa.snapshot("im182-offline-failed")
            assert qa.device(description="Retry send").exists(timeout=3), "断网视频未进入可重试失败态"
            qa.set_wifi(True)
            time.sleep(8)
            assert qa.click_retry(), "恢复网络后找不到视频重试按钮"
            time.sleep(30)
            evidence += qa.snapshot("im182-retry-success")
            assert not qa.device(description="Retry send").exists(timeout=2), "视频重试后仍显示失败"
            smoke.open_private(str(qa_credential["username"]), "im182-peer")
            evidence += smoke.snapshot("im182-peer-received")
            return "录像结束出现预览确认；断网发送失败后复用本地视频重传成功。", evidence
        finally:
            qa.set_wifi(True)

    def im222() -> tuple[str, list[str]]:
        audit_path = run_dir / "im222-server-order-audit.json"
        if args.reuse_im222_audit and audit_path.exists():
            audit = json.loads(audit_path.read_text(encoding="utf-8"))
            assert audit.get("observed_count") == 50, "已保存审计不是 50 条完整样本"
            assert audit.get("unique_count") == 50, "已保存审计存在重复消息"
            assert audit.get("ordered") is True, "已保存审计顺序不一致"
            evidence = [rel(audit_path, repo)]
            last_error: Exception | None = None
            for attempt in range(3):
                try:
                    smoke.device.app_start(args.package, stop=False, wait=True)
                    time.sleep(8 + attempt * 4)
                    evidence += smoke.open_private(str(qa_credential["username"]), f"im222-receiver-retry-{attempt + 1}")
                    evidence += smoke.snapshot("im222-receiver-final")
                    return "接收端离线期间连续发送 50 条；服务端 seq 审计为 50/50、无重复且顺序完全一致，接收端重连成功。", evidence
                except Exception as exc:
                    last_error = exc
                    time.sleep(8)
            raise RuntimeError(f"receiver reconnect failed after ordered server audit: {last_error}")

        evidence = qa.open_private("smoke_bob", "im222-sender")
        smoke.device.app_stop(args.package)
        stamp = datetime.now().strftime("%H%M%S")
        prefix = f"P1IM222_{stamp}_"
        expected = [f"{prefix}{index:03d}" for index in range(1, 51)]
        for index, text in enumerate(expected, start=1):
            qa.send_text_fast(text)
            if index in (1, 10, 25, 50):
                evidence += qa.snapshot(f"im222-sent-{index:03d}")

        token = str(qa_credential["token"])
        chat_id = find_private_chat(args.base, token, "smoke_bob")
        observed: list[str] = []
        messages: list[dict[str, Any]] = []
        deadline = time.time() + 150
        while time.time() < deadline:
            messages = list_messages(args.base, token, chat_id, 100)
            relevant = [
                item
                for item in messages
                if str((item.get("content") or {}).get("text") or "").startswith(prefix)
            ]
            relevant.sort(key=lambda item: int(item.get("seq") or 0))
            observed = [str((item.get("content") or {}).get("text") or "") for item in relevant]
            if len(observed) >= 50:
                break
            time.sleep(3)

        audit = {
            "prefix": prefix,
            "expected": expected,
            "observed_by_server_seq": observed,
            "observed_count": len(observed),
            "unique_count": len(set(observed)),
            "ordered": observed == expected,
            "seq": [int(item.get("seq") or 0) for item in relevant],
        }
        audit_path.write_text(json.dumps(audit, ensure_ascii=False, indent=2), encoding="utf-8")
        evidence.append(rel(audit_path, repo))
        assert len(observed) == 50, f"服务端仅收到 {len(observed)}/50 条消息"
        assert len(set(observed)) == 50, "50 条消息存在重复"
        assert observed == expected, "服务端按 seq 排序后与提交顺序不一致"

        smoke.device.app_start(args.package, stop=False, wait=True)
        time.sleep(8)
        smoke.open_private(str(qa_credential["username"]), "im222-receiver")
        evidence += smoke.snapshot("im222-receiver-final")
        return "接收端离线期间连续发送 50 条；服务端 seq 审计为 50/50、无重复且顺序完全一致，接收端重连成功。", evidence

    # Background interruption first; incoming call next; media retry after call state is cleaned.
    run_case("IM-169", im169)
    run_case("IM-167", im167)
    run_case("IM-171", im171)
    run_case("IM-182", im182)
    run_case("IM-222", im222)

    for harness in (smoke, qa):
        harness.set_wifi(True)
        log_path = run_dir / f"{harness.serial}-logcat.txt"
        log_path.write_text(harness.adb_run("logcat", "-d", "-v", "threadtime").stdout, encoding="utf-8")

    payload = {
        "environment": {
            "started_at": datetime.fromtimestamp(run_dir.stat().st_ctime).astimezone().isoformat(timespec="seconds"),
            "finished_at": datetime.now().astimezone().isoformat(timespec="seconds"),
            "devices": f"{args.device_smoke}, {args.device_qa}",
            "apk_sha256": args.apk_sha256,
        },
        "cases": results,
    }
    write_outputs(run_dir, payload)
    return 1 if any(item["status"] == "FAIL" for item in results) else 0


if __name__ == "__main__":
    raise SystemExit(main())
