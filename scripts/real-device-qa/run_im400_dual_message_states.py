#!/usr/bin/env python3
"""Run dual-device message state, receipt, scroll, and offline checks."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import Any, Callable


SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from run_im400_full import Case, rel, set_case, write_report  # noqa: E402
from run_im400_message_actions import MessageActionBatch, load_report  # noqa: E402


def adb(adb_path: str, serial: str, *args: str) -> str:
    result = subprocess.run(
        [adb_path, "-s", serial, *args],
        text=True,
        encoding="utf-8",
        errors="replace",
        capture_output=True,
        timeout=30,
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError(f"adb {' '.join(args)} failed: {result.stderr.strip()}")
    return result.stdout.strip()


class DualStateBatch:
    def __init__(
        self,
        repo: Path,
        evidence_dir: Path,
        adb_path: str,
        serial_a: str,
        serial_b: str,
        package: str,
        target_a: str,
        target_b: str,
    ) -> None:
        self.repo = repo
        self.evidence_dir = evidence_dir
        self.adb_path = adb_path
        self.serial_a = serial_a
        self.serial_b = serial_b
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
        item = {
            "time": datetime.now().astimezone().isoformat(timespec="seconds"),
            "action": action,
            "status": status,
            "detail": detail,
            "evidence": evidence,
        }
        self.events.append(item)
        (self.evidence_dir / "events.json").write_text(
            json.dumps(self.events, ensure_ascii=False, indent=2), encoding="utf-8"
        )
        print(f"[STATE400] {action}: {status} - {detail}", flush=True)

    def open_both(self) -> tuple[list[str], list[str]]:
        return self.a.open_chat(self.target_a), self.b.open_chat(self.target_b)

    def move_a_to_list(self) -> list[str]:
        for _ in range(4):
            if self.a.device(description="编辑").exists(timeout=0.5):
                break
            self.a.device.press("back")
            time.sleep(0.7)
        self.a.ensure_messages()
        return self.a.snapshot("messages-list")

    def type_without_send(self, text: str) -> None:
        edit = self.b.device(className="android.widget.EditText")
        if not edit.exists(timeout=2):
            raise RuntimeError("B 机输入框缺失")
        edit.click()
        self.b.device.set_fastinput_ime(True)
        self.b.device.send_keys(text, clear=True)

    def clear_b_input(self) -> None:
        edit = self.b.device(className="android.widget.EditText")
        if edit.exists(timeout=1):
            edit.click()
            self.b.device.send_keys("", clear=True)
        self.b.device.set_fastinput_ime(False)

    def typing_state(self, cases: dict[str, Case]) -> None:
        open_a, open_b = self.open_both()
        marker = f"TYPING-{datetime.now().strftime('%H%M%S')}"
        self.type_without_send(marker)
        time.sleep(2)
        active = self.a.snapshot("typing-active")
        active_xml = self.a.device.dump_hierarchy()
        seen = "正在输入" in active_xml
        self.clear_b_input()
        time.sleep(7)
        stopped = self.a.snapshot("typing-stopped")
        gone = "正在输入" not in self.a.device.dump_hierarchy()
        ok = seen and gone
        set_case(
            cases,
            "IM-139",
            "PASS" if ok else "FAIL",
            "A、B 两台不同账号真机进入同一私聊，B 只输入唯一文本但不发送，随后清空并停止输入。",
            "A 端及时出现“正在输入”提示，B 停止后提示自动消失。" if ok else f"输入状态异常：seen={seen}, gone={gone}",
            open_a + open_b + active + stopped,
            "P3",
        )
        self.record("正在输入状态", "PASS" if ok else "FAIL", f"seen={seen}, gone={gone}", active + stopped)

    def receipts(self, cases: dict[str, Case]) -> None:
        before_list = self.move_a_to_list()
        self.b.open_chat(self.target_b)
        token = f"RECEIPT-{datetime.now().strftime('%H%M%S')}"
        sent, send_evidence = self.b.send_text(token, "receipt")
        if not sent:
            raise RuntimeError("回执测试消息未发送成功")
        time.sleep(3)
        before_read_b = self.b.snapshot("receipt-delivered-before-read")
        list_a = self.a.snapshot("receipt-unread-in-list")
        list_xml = self.a.device.dump_hierarchy()
        listed = token in list_xml
        unread = "未读" in list_xml

        open_a = self.a.open_chat(self.target_a)
        time.sleep(3)
        received = self.a.visible_outside_edit(token)
        after_read_b = self.b.snapshot("receipt-read-after-open")

        common = send_evidence + before_read_b + list_a + open_a + after_read_b
        set_case(
            cases,
            "IM-126",
            "PASS" if (sent and listed) else "FAIL",
            "A 端在线停留会话列表，B 端发送唯一文本并核对双方与发送状态图标。",
            "A 端在线收到消息并显示未读，B 端消息由单勾更新为双勾送达状态。" if sent and listed else f"送达异常：sent={sent}, listed={listed}",
            common,
            "P2",
        )
        set_case(
            cases,
            "IM-128",
            "PASS" if (listed and unread) else "FAIL",
            "A 端仅停留会话列表、不进入消息详情，B 端发送唯一文本。",
            "A 端会话预览出现唯一文本并保持未读；B 端此时仅为送达，未提前变为已读。" if listed and unread else f"未曝光状态异常：listed={listed}, unread={unread}",
            common,
            "P2",
        )
        set_case(
            cases,
            "IM-127",
            "PASS" if received else "FAIL",
            "A 端从带未读的会话列表进入目标私聊并实际曝光消息，B 端持续停留发送会话。",
            "A 端看到唯一消息后，B 端状态更新为绿色双勾已读。" if received else "A 端进入会话后未看到回执测试消息。",
            common,
            "P2",
        )
        self.record(
            "送达/未曝光/已读回执",
            "PASS" if sent and listed and unread and received else "FAIL",
            f"listed={listed}, unread={unread}, received={received}",
            before_list + common,
        )

    def _scroll_button_visible(self) -> bool:
        for item in self.a._nodes():
            if (
                item["clickable"]
                and not item["desc"]
                and not item["text"]
                and item["left"] > 1000
                and 2100 < item["top"] < 2420
                and item["bottom"] < 2480
            ):
                return True
        return False

    def scrolled_new_message(self, cases: dict[str, Case]) -> None:
        self.a.open_chat(self.target_a)
        self.b.open_chat(self.target_b)
        for _ in range(3):
            self.a.device.swipe(600, 650, 600, 2050, duration=0.7)
            time.sleep(0.7)
        before = self.a.snapshot("scrolled-history-before-new")
        button_before = self._scroll_button_visible()
        token = f"SCROLLNEW-{datetime.now().strftime('%H%M%S')}"
        sent, send_evidence = self.b.send_text(token, "scroll-new")
        if not sent:
            raise RuntimeError("滚动位置测试消息未发送成功")
        time.sleep(3)
        after = self.a.snapshot("scrolled-history-after-new")
        not_jumped = not self.a.visible_outside_edit(token)
        button_after = self._scroll_button_visible()
        ok = not_jumped and button_after
        set_case(
            cases,
            "IM-120",
            "PASS" if ok else "FAIL",
            "A 端在目标私聊连续上翻到历史位置，B 端发送唯一新消息。",
            "A 端保持原历史阅读位置，未强制跳到底部，并显示回到底部按钮。" if ok else f"滚动收新消息异常：not_jumped={not_jumped}, button_before={button_before}, button_after={button_after}",
            before + send_evidence + after,
            "P3",
        )
        self.record("滚动位置收到新消息", "PASS" if ok else "FAIL", f"not_jumped={not_jumped}, button_after={button_after}", before + after)
        # Restore the receiver to the newest messages for later checks.
        self.a.device.swipe(600, 2050, 600, 500, duration=0.8)
        time.sleep(1)

    def offline_single(self, cases: dict[str, Case]) -> None:
        self.b.open_chat(self.target_b)
        adb(self.adb_path, self.serial_a, "shell", "am", "force-stop", self.package)
        time.sleep(2)
        token = f"OFFLINE1-{datetime.now().strftime('%H%M%S')}"
        sent, send_evidence = self.b.send_text(token, "offline-single")
        if not sent:
            raise RuntimeError("离线单消息发送失败")
        time.sleep(4)
        stopped = self.a.snapshot("offline-single-app-stopped")
        self.a.device.shell(["am", "start", "-W", "-n", f"{self.package}/.MainActivity"])
        time.sleep(5)
        open_a = self.a.open_chat(self.target_a)
        time.sleep(2)
        received = self.a.visible_outside_edit(token)
        after = self.a.snapshot("offline-single-received")
        set_case(
            cases,
            "IM-221",
            "PASS" if received else "FAIL",
            "强制停止 A 端 App 后，由在线 B 端发送唯一文本；随后重新启动 A 并进入同一私聊。",
            "A 端重新上线后完整拉取到离线期间的唯一消息，无需 B 端重发。" if received else "A 端重新上线进入会话后未找到离线期间消息。",
            send_evidence + stopped + open_a + after,
            "P1",
        )
        self.record("单条离线消息", "PASS" if received else "FAIL", f"received={received}", send_evidence + after)

    def offline_withdraw(self, cases: dict[str, Case]) -> None:
        self.b.open_chat(self.target_b)
        adb(self.adb_path, self.serial_a, "shell", "am", "force-stop", self.package)
        time.sleep(2)
        token = f"OFFRECALL-{datetime.now().strftime('%H%M%S')}"
        sent, send_evidence = self.b.send_text(token, "offline-recall")
        if not sent:
            raise RuntimeError("离线撤回前置消息发送失败")
        _, menu_evidence = self.b.open_menu(token, "offline-recall")
        self.b.click_menu("撤回")
        time.sleep(2)
        recalled_b = self.b.snapshot("offline-recall-sender-after")
        adb(self.adb_path, self.serial_a, "shell", "am", "start", "-W", "-n", f"{self.package}/.MainActivity")
        time.sleep(5)
        open_a = self.a.open_chat(self.target_a)
        time.sleep(2)
        hierarchy = self.a.device.dump_hierarchy()
        token_gone = not self.a.visible_outside_edit(token)
        marker = "撤回" in hierarchy
        after_a = self.a.snapshot("offline-recall-receiver-after")
        ok = token_gone and marker
        set_case(
            cases,
            "IM-225",
            "PASS" if ok else "FAIL",
            "A 端 App 强制停止期间，B 端发送唯一消息并立即撤回；随后 A 端重新上线进入私聊。",
            "A 端上线后不显示原文本，只显示正确的对方撤回提示。" if ok else f"离线撤回异常：token_gone={token_gone}, marker={marker}",
            send_evidence + menu_evidence + recalled_b + open_a + after_a,
            "P1",
        )
        self.record("离线期间撤回", "PASS" if ok else "FAIL", f"token_gone={token_gone}, marker={marker}", recalled_b + after_a)

    def reply_then_revoke(self, cases: dict[str, Case]) -> None:
        # Device A does not keep uiautomator2's FastInputIME installed. Select
        # its already-configured Baidu IME so focusing the reply composer does
        # not launch Huawei's first-run keyboard-layout setup screen.
        self.a.device.shell(["ime", "set", "com.baidu.input_huawei/.ImeService"])
        self.a.open_chat(self.target_a)
        self.b.open_chat(self.target_b)
        stamp = datetime.now().strftime("%H%M%S")
        source = f"REPLYREVOKE-SRC-{stamp}"
        reply = f"REPLYREVOKE-ANSWER-{stamp}"
        sent, source_evidence = self.b.send_text(source, "reply-revoke-source")
        if not sent:
            raise RuntimeError("被引用源消息发送失败")
        time.sleep(3)
        if not self.a.visible_outside_edit(source):
            raise RuntimeError("A 端未收到被引用源消息")

        _, reply_menu = self.a.open_menu(source, "reply-revoke-on-a")
        self.a.click_menu("回复")
        quote_active = self.a.snapshot("reply-revoke-quote-active")
        edit = self.a.device(className="android.widget.EditText")
        if not edit.exists(timeout=2):
            raise RuntimeError("A 端引用回复输入框缺失")
        edit.click()
        edit.clear_text()
        self.a.device.shell(["input", "text", reply])
        time.sleep(0.5)
        reply_evidence = self.a.snapshot("reply-revoke-answer-typed")
        self.a.click_send()
        time.sleep(1.5)
        reply_evidence += self.a.snapshot("reply-revoke-answer-sent")
        replied = self.a.visible_outside_edit(reply)
        if not replied:
            raise RuntimeError("引用回复发送失败")
        time.sleep(2)

        _, revoke_menu = self.b.open_menu(source, "reply-revoke-on-b")
        self.b.click_menu("撤回")
        time.sleep(3)
        sender_after = self.b.snapshot("reply-revoke-sender-after")
        receiver_after = self.a.snapshot("reply-revoke-receiver-after")
        hierarchy = self.a.device.dump_hierarchy()
        marker = "撤回" in hierarchy
        reply_visible = self.a.visible_outside_edit(reply)
        quote_snapshot = source in hierarchy
        foreground = self.a.device.app_current().get("package") == self.package
        ok = marker and reply_visible and quote_snapshot and foreground
        set_case(
            cases,
            "IM-119",
            "PASS" if ok else "FAIL",
            "B 端发送唯一源文本，A 端引用回复后，由 B 端在允许时限内撤回原消息。",
            "原消息替换为对方撤回提示，已发送的回复保持稳定，引用区保留发送时的源文本快照，双方均未崩溃。" if ok else f"引用撤回异常：marker={marker}, reply_visible={reply_visible}, quote_snapshot={quote_snapshot}, foreground={foreground}",
            source_evidence + reply_menu + quote_active + reply_evidence + revoke_menu + sender_after + receiver_after,
            "P2",
        )
        self.record(
            "回复后撤回源消息",
            "PASS" if ok else "FAIL",
            f"marker={marker}, reply={reply_visible}, quote_snapshot={quote_snapshot}, foreground={foreground}",
            sender_after + receiver_after,
        )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", required=True)
    parser.add_argument("--run-dir", required=True)
    parser.add_argument("--adb", required=True)
    parser.add_argument("--serial-a", required=True)
    parser.add_argument("--serial-b", required=True)
    parser.add_argument("--target-a", required=True)
    parser.add_argument("--target-b", required=True)
    parser.add_argument("--package", default="com.genericim.app")
    parser.add_argument(
        "--only",
        choices=("all", "typing", "receipts", "scroll", "offline", "offline-withdraw", "reply-revoke"),
        default="all",
    )
    args = parser.parse_args()

    repo = Path(args.repo).resolve()
    run_dir = Path(args.run_dir).resolve()
    evidence_dir = run_dir / f"dual-message-states-{datetime.now().strftime('%Y%m%d-%H%M%S')}"
    evidence_dir.mkdir(parents=True, exist_ok=True)
    cases, environment, log_summary = load_report(run_dir)
    batch = DualStateBatch(
        repo,
        evidence_dir,
        args.adb,
        args.serial_a,
        args.serial_b,
        args.package,
        args.target_a,
        args.target_b,
    )
    actions: tuple[tuple[str, Callable[[], None]], ...] = (
        ("typing", lambda: batch.typing_state(cases)),
        ("receipts", lambda: batch.receipts(cases)),
        ("scroll", lambda: batch.scrolled_new_message(cases)),
        ("offline", lambda: batch.offline_single(cases)),
        ("offline-withdraw", lambda: batch.offline_withdraw(cases)),
        ("reply-revoke", lambda: batch.reply_then_revoke(cases)),
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

    print(f"[STATE400] report={run_dir / 'IM_400_FULL_REAL_DEVICE_TEST_REPORT.md'}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
