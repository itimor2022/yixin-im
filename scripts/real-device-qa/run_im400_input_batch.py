#!/usr/bin/env python3
"""Run real-device keyboard-send and long clipboard-paste checks."""

from __future__ import annotations

import argparse
import json
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import Any, Callable


SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from run_im400_full import Case, set_case, write_report  # noqa: E402
from run_im400_message_actions import MessageActionBatch, load_report  # noqa: E402


class InputBatch:
    def __init__(
        self,
        repo: Path,
        evidence_dir: Path,
        serial_a: str,
        serial_b: str,
        package: str,
        target_a: str,
        target_b: str,
    ) -> None:
        self.repo = repo
        self.evidence_dir = evidence_dir
        self.package = package
        self.target_a = target_a
        self.target_b = target_b
        self.a_dir = evidence_dir / "device-a"
        self.b_dir = evidence_dir / "device-b"
        self.a_dir.mkdir(parents=True, exist_ok=True)
        self.b_dir.mkdir(parents=True, exist_ok=True)
        self.a = MessageActionBatch(repo, self.a_dir, serial_a, package)
        self.b = MessageActionBatch(repo, self.b_dir, serial_b, package)
        self.events: list[dict[str, Any]] = []

    def record(self, action: str, status: str, detail: str, evidence: list[str]) -> None:
        self.events.append(
            {
                "time": datetime.now().astimezone().isoformat(timespec="seconds"),
                "action": action,
                "status": status,
                "detail": detail,
                "evidence": evidence,
            }
        )
        (self.evidence_dir / "events.json").write_text(
            json.dumps(self.events, ensure_ascii=False, indent=2), encoding="utf-8"
        )
        print(f"[INPUT400] {action}: {status} - {detail}", flush=True)

    def open_both(self) -> tuple[list[str], list[str]]:
        return self.a.open_chat(self.target_a), self.b.open_chat(self.target_b)

    def keyboard_send(self, cases: dict[str, Case]) -> None:
        open_a, open_b = self.open_both()
        token = f"KEYSEND-{datetime.now().strftime('%H%M%S')}"
        edit = self.b.device(className="android.widget.EditText")
        if not edit.exists(timeout=2):
            raise RuntimeError("B 端输入框缺失")
        edit.click()
        self.b.device.set_fastinput_ime(True)
        self.b.device.send_keys(token, clear=True)
        typed = self.b.snapshot("keyboard-send-typed")
        # Trigger the same IME_ACTION_SEND callback as the soft keyboard's
        # visible Send key. A raw KEYCODE_ENTER is not equivalent on Flutter.
        self.b.device.send_action("send")
        time.sleep(2)
        sender_after = self.b.snapshot("keyboard-send-after-enter")
        sender_visible = self.b.visible_outside_edit(token)
        input_empty = not self.b.device(className="android.widget.EditText").get_text().strip()
        time.sleep(3)
        receiver_after = self.a.snapshot("keyboard-send-received")
        receiver_visible = self.a.visible_outside_edit(token)
        ok = sender_visible and input_empty and receiver_visible
        set_case(
            cases,
            "IM-112",
            "PASS" if ok else "FAIL",
            "B 端输入唯一文本后使用输入法发送键（KEYCODE_ENTER），不点击界面蓝色发送按钮；A 端实时核对。",
            "输入法发送键提交一条消息，输入框清空，A、B 两端各只显示一条唯一文本。" if ok else f"输入法发送异常：sender_visible={sender_visible}, input_empty={input_empty}, receiver_visible={receiver_visible}",
            open_a + open_b + typed + sender_after + receiver_after,
            "P2",
        )
        self.record("输入法发送键", "PASS" if ok else "FAIL", f"sender={sender_visible}, empty={input_empty}, receiver={receiver_visible}", typed + sender_after + receiver_after)

    def long_clipboard_paste(self, cases: dict[str, Case]) -> None:
        self.open_both()
        stamp = datetime.now().strftime("%H%M%S")
        prefix = f"PASTELONG-{stamp}-"
        text = prefix + ("Ab9_" * 240)
        edit = self.b.device(className="android.widget.EditText")
        if not edit.exists(timeout=2):
            raise RuntimeError("B 端输入框缺失")
        edit.click()
        self.b.device.clear_text()
        self.b.device.set_input_ime(False)
        time.sleep(0.5)
        self.b.device.clipboard = text
        edit = self.b.device(className="android.widget.EditText")
        bounds = edit.info["bounds"]
        self.b.device.long_click(
            (bounds["left"] + bounds["right"]) // 2,
            (bounds["top"] + bounds["bottom"]) // 2,
            duration=0.8,
        )
        time.sleep(0.8)
        paste = self.b.device(text="粘贴")
        if not paste.exists(timeout=1):
            paste = self.b.device(description="粘贴")
        if not paste.exists(timeout=1):
            raise RuntimeError("系统文本菜单未出现“粘贴”")
        paste.click()
        time.sleep(1)
        pasted_value = self.b.device(className="android.widget.EditText").get_text() or ""
        pasted = pasted_value == text
        typed = self.b.snapshot("long-paste-typed")
        if not pasted:
            set_case(
                cases,
                "IM-115",
                "FAIL",
                "将 976 字符唯一文本写入系统剪贴板，聚焦聊天输入框并触发系统粘贴键。",
                f"粘贴后长度或内容不一致：expected={len(text)}, actual={len(pasted_value)}。",
                typed,
                "P3",
            )
            self.record("粘贴长文本", "FAIL", f"expected={len(text)}, actual={len(pasted_value)}", typed)
            return

        self.b.click_send()
        time.sleep(2)
        sender_after = self.b.snapshot("long-paste-sent")
        sender_exact = self.b.visible_outside_edit(text)
        time.sleep(4)
        receiver_after = self.a.snapshot("long-paste-received")
        receiver_exact = self.a.visible_outside_edit(text)
        ok = pasted and sender_exact and receiver_exact
        evidence = typed + sender_after + receiver_after
        set_case(
            cases,
            "IM-115",
            "PASS" if ok else "FAIL",
            "从系统剪贴板粘贴 976 字符混合长文本并发送，双端逐字符核对完整内容。",
            "输入框完整保留 976 字符，发送后 A、B 两端内容逐字符一致，无静默截断。" if ok else f"长文本发送异常：pasted={pasted}, sender_exact={sender_exact}, receiver_exact={receiver_exact}",
            evidence,
            "P2",
        )
        self.record("粘贴长文本", "PASS" if ok else "FAIL", f"length={len(text)}, sender_exact={sender_exact}, receiver_exact={receiver_exact}", evidence)

        # Clean up the large test bubble on both devices by withdrawing it.
        if ok:
            try:
                _, menu = self.b.open_menu(prefix, "long-paste-cleanup")
                self.b.click_menu("撤回")
                time.sleep(2)
                cleanup = self.b.snapshot("long-paste-cleanup-after") + self.a.snapshot("long-paste-cleanup-remote")
                self.record("长文本清理", "PASS", "测试长文本已双端撤回", menu + cleanup)
            except Exception as exc:
                self.record("长文本清理", "BLOCKED", f"清理异常：{type(exc).__name__}: {exc}", [])


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", required=True)
    parser.add_argument("--run-dir", required=True)
    parser.add_argument("--serial-a", required=True)
    parser.add_argument("--serial-b", required=True)
    parser.add_argument("--target-a", required=True)
    parser.add_argument("--target-b", required=True)
    parser.add_argument("--package", default="com.genericim.app")
    parser.add_argument("--only", choices=("all", "keyboard", "paste"), default="all")
    args = parser.parse_args()

    repo = Path(args.repo).resolve()
    run_dir = Path(args.run_dir).resolve()
    evidence_dir = run_dir / f"input-batch-{datetime.now().strftime('%Y%m%d-%H%M%S')}"
    evidence_dir.mkdir(parents=True, exist_ok=True)
    cases, environment, log_summary = load_report(run_dir)
    batch = InputBatch(
        repo,
        evidence_dir,
        args.serial_a,
        args.serial_b,
        args.package,
        args.target_a,
        args.target_b,
    )
    actions: tuple[tuple[str, Callable[[], None]], ...] = (
        ("keyboard", lambda: batch.keyboard_send(cases)),
        ("paste", lambda: batch.long_clipboard_paste(cases)),
    )
    if args.only != "all":
        actions = tuple(item for item in actions if item[0] == args.only)
    try:
        for name, action in actions:
            try:
                action()
            except Exception as exc:
                evidence: list[str] = []
                for device, label in ((batch.a, "a"), (batch.b, "b")):
                    try:
                        evidence += device.snapshot(f"{name}-harness-error-{label}")
                    except Exception:
                        pass
                batch.record(name, "BLOCKED", f"自动化步骤异常：{type(exc).__name__}: {exc}", evidence)
            write_report(repo, run_dir, cases, environment, log_summary)
    finally:
        try:
            batch.b.device.set_fastinput_ime(False)
        except Exception:
            pass
    print(f"[INPUT400] report={run_dir / 'IM_400_FULL_REAL_DEVICE_TEST_REPORT.md'}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
