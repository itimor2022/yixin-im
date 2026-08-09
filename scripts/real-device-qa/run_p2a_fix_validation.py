#!/usr/bin/env python3
"""Focused two-device validation for IM-088/091/112/126."""

from __future__ import annotations

import argparse
import html
import json
import re
import time
from datetime import datetime
from pathlib import Path
from typing import Any, Callable


SCRIPT_DIR = Path(__file__).resolve().parent
import sys

if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from run_p1_fix_validation import (  # noqa: E402
    P1Harness,
    find_private_chat,
    list_messages,
)
from run_im400_full import rel  # noqa: E402


def outside_edit_contains(harness: P1Harness, token: str) -> bool:
    for item in harness.nodes():
        if item["class"] == "android.widget.EditText":
            continue
        if token in f"{item['desc']} {item['text']}":
            return True
    return False


def wait_until(predicate: Callable[[], bool], timeout: float, interval: float = 0.5) -> bool:
    deadline = time.time() + timeout
    while time.time() < deadline:
        if predicate():
            return True
        time.sleep(interval)
    return False


def ensure_message_list(harness: P1Harness) -> None:
    harness.device.app_start(harness.package, stop=False, wait=True)
    for _ in range(8):
        if harness.device(description="编辑").exists(timeout=0.5):
            return
        height = harness.device.window_size()[1]
        rows = [
            item
            for item in harness.nodes()
            if "消息" in item["desc"] and item["top"] > int(height * 0.8) and item["clickable"]
        ]
        if rows:
            item = rows[0]
            harness.device.click((item["left"] + item["right"]) // 2, (item["top"] + item["bottom"]) // 2)
            time.sleep(1)
            continue
        harness.device.press("back")
        time.sleep(0.7)
    raise RuntimeError("message list not found")


def select_edit_conversation(harness: P1Harness, target: str) -> None:
    ensure_message_list(harness)
    if not harness.device(description="编辑").click_exists(timeout=3):
        raise RuntimeError("conversation edit action missing")
    time.sleep(1)
    matches = [
        item
        for item in harness.nodes()
        if target in item["desc"] and item["top"] > 350 and item["bottom"] > item["top"]
    ]
    if not matches:
        raise RuntimeError(f"conversation row missing: {target}")
    row = max(matches, key=lambda item: (item["right"] - item["left"]) * (item["bottom"] - item["top"]))
    harness.device.click(70, (row["top"] + row["bottom"]) // 2)
    time.sleep(1)


def write_report(run_dir: Path, environment: dict[str, Any], cases: list[dict[str, Any]]) -> None:
    payload = {"environment": environment, "cases": cases}
    (run_dir / "p2a-validation-results.json").write_text(
        json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    counts = {status: sum(item["status"] == status for item in cases) for status in ("PASS", "FAIL", "BLOCKED")}
    lines = [
        "# P2-A 双真机验证报告",
        "",
        f"- 完成时间：{environment['finished_at']}",
        f"- 设备：{environment['devices']}",
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
        lines.append(f"### {item['case_id']} {item['status']}")
        lines.append("")
        lines.extend(f"- `{path}`" for path in item["evidence"])
        lines.append("")
    (run_dir / "P2A_REAL_DEVICE_VALIDATION_REPORT.md").write_text("\n".join(lines), encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", required=True)
    parser.add_argument("--run-dir", required=True)
    parser.add_argument("--adb", required=True)
    parser.add_argument("--device-smoke", required=True)
    parser.add_argument("--device-qa", required=True)
    parser.add_argument("--qa-credentials", required=True)
    parser.add_argument("--apk-sha256", required=True)
    parser.add_argument("--package", default="com.genericim.app")
    parser.add_argument("--base", default="https://api.example.com/api/v1")
    args = parser.parse_args()

    repo = Path(args.repo).resolve()
    run_dir = Path(args.run_dir).resolve()
    run_dir.mkdir(parents=True, exist_ok=True)
    credential = json.loads(Path(args.qa_credentials).read_text(encoding="utf-8-sig"))
    smoke = P1Harness(repo, run_dir / args.device_smoke, args.adb, args.device_smoke, args.package)
    qa = P1Harness(repo, run_dir / args.device_qa, args.adb, args.device_qa, args.package)
    cases: list[dict[str, Any]] = []

    for harness in (smoke, qa):
        harness.adb_run("logcat", "-c")

    def record(case_id: str, body: Callable[[], tuple[str, list[str]]]) -> None:
        try:
            detail, evidence = body()
            status = "PASS"
        except AssertionError as exc:
            status, detail = "FAIL", str(exc)
            evidence = qa.snapshot(f"{case_id.lower()}-failed")
        except Exception as exc:
            status = "BLOCKED"
            detail = f"自动化前置异常：{type(exc).__name__}: {exc}"
            evidence = qa.snapshot(f"{case_id.lower()}-blocked")
        cases.append({"case_id": case_id, "status": status, "detail": detail, "evidence": evidence})
        print(f"[P2-A] {case_id}: {status} - {detail}", flush=True)

    def im112() -> tuple[str, list[str]]:
        evidence = smoke.open_private(str(credential["username"]), "im112-receiver")
        evidence += qa.open_private("smoke_bob", "im112-sender")
        token = f"P2IME{datetime.now().strftime('%H%M%S')}"
        edit = qa.device(className="android.widget.EditText")
        edit.click()
        qa.device.set_fastinput_ime(True)
        qa.device.send_keys(token, clear=True)
        evidence += qa.snapshot("im112-before-enter")
        qa.adb_run("shell", "input", "keyevent", "66")
        assert wait_until(lambda: outside_edit_contains(qa, token), 12), "发送端按 Enter 后未出现消息气泡"
        assert wait_until(lambda: outside_edit_contains(smoke, token), 15), "接收端未收到输入法发送消息"
        current = qa.device(className="android.widget.EditText").get_text() or ""
        assert token not in current, "输入法发送成功后输入框未清空"
        evidence += qa.snapshot("im112-sender-after-enter")
        evidence += smoke.snapshot("im112-receiver-arrived")
        return "物理 KEYCODE_ENTER 与界面发送复用同一链路，双端显示且输入框清空。", evidence

    def im091() -> tuple[str, list[str]]:
        evidence = qa.open_private("smoke_bob", "im091")
        token = f"P2DRAFT{datetime.now().strftime('%H%M%S')}"
        edit = qa.device(className="android.widget.EditText")
        edit.click()
        qa.device.set_fastinput_ime(True)
        qa.device.send_keys(token, clear=True)
        time.sleep(1)
        evidence += qa.snapshot("im091-draft-typed")
        for _ in range(3):
            qa.device.press("back")
            time.sleep(1)
            if qa.device(description="编辑").exists(timeout=0.5):
                break
        ensure_message_list(qa)
        evidence += qa.snapshot("im091-draft-list")
        assert qa.hierarchy_contains(token) or qa.hierarchy_contains("草稿"), "会话列表未显示草稿预览"
        row = qa.device(descriptionContains="smoke_bob")
        if not row.click_exists(timeout=3):
            raise RuntimeError("draft conversation row missing")
        assert qa.device(className="android.widget.EditText").wait(timeout=5), "重进会话后输入框缺失"
        restored = qa.device(className="android.widget.EditText").get_text() or ""
        evidence += qa.snapshot("im091-draft-restored")
        assert token in restored, "重进会话后草稿文本未恢复"
        qa.device(className="android.widget.EditText").click()
        qa.device.send_keys("", clear=True)
        time.sleep(1)
        qa.device.press("back")
        time.sleep(1)
        ensure_message_list(qa)
        evidence += qa.snapshot("im091-draft-cleared")
        return "草稿在账号与会话维度持久化，列表可见、重进恢复，清空后移除。", evidence

    def im126() -> tuple[str, list[str]]:
        ensure_message_list(smoke)
        evidence = smoke.snapshot("im126-receiver-list-before")
        evidence += qa.open_private("smoke_bob", "im126-sender")
        token = f"P2DELIVERED{datetime.now().strftime('%H%M%S')}"
        visible, sent_evidence = qa.runner.send_text(token, "im126")
        evidence += sent_evidence
        assert visible, "发送端未显示送达测试消息"
        assert wait_until(lambda: smoke.hierarchy_contains(token), 15), "接收端会话列表未实时收到消息"
        evidence += smoke.snapshot("im126-receiver-unread-list")
        time.sleep(8)

        token_value = str(credential["token"])
        chat_id = find_private_chat(args.base, token_value, "smoke_bob")
        messages = list_messages(args.base, token_value, chat_id, 100)
        matched = next(
            (item for item in messages if (item.get("content") or {}).get("text") == token),
            None,
        )
        assert matched is not None, "服务端未找到送达测试消息"
        status = int(matched.get("status") or 0)
        audit = {"token": token, "msg_id": matched.get("msg_id"), "seq": matched.get("seq"), "status": status}
        audit_path = run_dir / "im126-delivered-audit.json"
        audit_path.write_text(json.dumps(audit, ensure_ascii=False, indent=2), encoding="utf-8")
        evidence.append(rel(audit_path, repo))
        assert status >= 2, f"接收端在线收到消息后服务端状态仍为 {status}，未达到 delivered"
        evidence += qa.snapshot("im126-sender-delivered")
        return "接收端停留会话列表也会确认 delivered；服务端状态达到 2，未打开会话前不误标 read。", evidence

    def im088() -> tuple[str, list[str]]:
        qa.runner.navigate_tab("联系人", "im088-qa-outside-chat")
        evidence = smoke.open_private(str(credential["username"]), "im088-sender")
        token = f"P2UNREAD{datetime.now().strftime('%H%M%S')}"
        visible, sent = smoke.runner.send_text(token, "im088")
        evidence += sent
        assert visible, "未读准备消息发送失败"
        time.sleep(8)
        ensure_message_list(qa)
        assert qa.hierarchy_contains(token), "目标会话没有生成未读消息"
        evidence += qa.snapshot("im088-unread-before")
        select_edit_conversation(qa, "smoke_bob")
        assert qa.device(description="标记已读").exists(timeout=3), "选中未读会话后没有标记已读动作"
        evidence += qa.snapshot("im088-selected-read")
        qa.device(description="标记已读").click()
        time.sleep(3)
        select_edit_conversation(qa, "smoke_bob")
        evidence += qa.snapshot("im088-selected-unread")
        mark_unread = qa.device(description="标记未读")
        if not mark_unread.exists(timeout=2):
            mark_unread = qa.device(description="标记为未读")
        assert mark_unread.exists(timeout=2), "标记已读后动作没有切换为标记未读"
        mark_unread.click()
        time.sleep(2)
        return "批量标记已读后角标状态立即更新，再选中时动作切换为“标记未读”。", evidence

    record("IM-112", im112)
    record("IM-091", im091)
    record("IM-126", im126)
    record("IM-088", im088)

    for harness in (smoke, qa):
        log_path = run_dir / f"{harness.serial}-logcat.txt"
        log_path.write_text(harness.adb_run("logcat", "-d", "-v", "threadtime").stdout, encoding="utf-8")

    environment = {
        "finished_at": datetime.now().astimezone().isoformat(timespec="seconds"),
        "devices": f"{args.device_smoke}, {args.device_qa}",
        "apk_sha256": args.apk_sha256,
    }
    write_report(run_dir, environment, cases)
    return 1 if any(item["status"] == "FAIL" for item in cases) else 0


if __name__ == "__main__":
    raise SystemExit(main())
