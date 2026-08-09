#!/usr/bin/env python3
"""Run real-device message action checks against freshly-created messages.

Destructive actions are limited to unique messages created by this run. A
harness exception is recorded as BLOCKED in the batch event log and never
overwrites the checklist case with a product failure.
"""

from __future__ import annotations

import argparse
import html
import json
import re
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import Any, Callable

import uiautomator2 as u2


SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from run_im400_full import Case, rel, set_case, write_report  # noqa: E402


def decode_xml_value(value: str) -> str:
    decoded = value
    for _ in range(3):
        next_value = html.unescape(decoded)
        if next_value == decoded:
            break
        decoded = next_value
    return decoded


def load_report(run_dir: Path) -> tuple[dict[str, Case], dict[str, Any], dict[str, Any] | None]:
    payload = json.loads((run_dir / "results.json").read_text(encoding="utf-8"))
    cases = {item["case_id"]: Case(**item) for item in payload["cases"]}
    return cases, payload["environment"], payload.get("logcat_summary")


class MessageActionBatch:
    def __init__(self, repo: Path, evidence_dir: Path, serial: str, package: str) -> None:
        self.repo = repo
        self.evidence_dir = evidence_dir
        self.serial = serial
        self.package = package
        self.device = u2.connect(serial)
        self.step = 0
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
        print(f"[MSG400] {action}: {status} - {detail}", flush=True)

    def snapshot(self, name: str) -> list[str]:
        self.step += 1
        png = self.evidence_dir / f"{self.step:03d}-{name}.png"
        xml = self.evidence_dir / f"{self.step:03d}-{name}.xml"
        self.device.screenshot(str(png))
        xml.write_text(self.device.dump_hierarchy(), encoding="utf-8")
        return [rel(png, self.repo), rel(xml, self.repo)]

    def _nodes(self) -> list[dict[str, Any]]:
        rows: list[dict[str, Any]] = []
        for node in re.findall(r"<node\b[^>]*>", self.device.dump_hierarchy()):
            bounds = re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', node)
            if not bounds:
                continue
            desc = re.search(r'content-desc="([^"]*)"', node)
            text = re.search(r'text="([^"]*)"', node)
            class_name = re.search(r'class="([^"]*)"', node)
            package = re.search(r'package="([^"]*)"', node)
            rows.append(
                {
                    "desc": decode_xml_value(desc.group(1)) if desc else "",
                    "text": decode_xml_value(text.group(1)) if text else "",
                    "class": class_name.group(1) if class_name else "",
                    "package": package.group(1) if package else "",
                    "left": int(bounds.group(1)),
                    "top": int(bounds.group(2)),
                    "right": int(bounds.group(3)),
                    "bottom": int(bounds.group(4)),
                    "clickable": 'clickable="true"' in node,
                }
            )
        return rows

    def ensure_messages(self) -> None:
        self.device.app_start(self.package, stop=False, wait=True)
        time.sleep(1.5)
        if self.device.app_current().get("package") != self.package:
            self.device.shell(["am", "start", "-W", "-n", f"{self.package}/.MainActivity"])
            time.sleep(3)
        for _ in range(8):
            if self.device(description="编辑").exists(timeout=0.5):
                return
            height = self.device.window_size()[1]
            tabs = [
                item
                for item in self._nodes()
                if "消息" in item["desc"] and item["top"] > int(height * 0.80) and item["clickable"]
            ]
            if tabs:
                item = tabs[0]
                self.device.click(
                    (item["left"] + item["right"]) // 2,
                    (item["top"] + item["bottom"]) // 2,
                )
                time.sleep(1)
                continue
            for label in ("取消", "完成"):
                if self.device(description=label).click_exists(timeout=0.3):
                    time.sleep(0.8)
                    break
            else:
                self.device.press("back")
                time.sleep(0.6)
        raise RuntimeError("消息会话列表未找到")

    def open_chat(self, target: str) -> list[str]:
        self.ensure_messages()
        rows: list[dict[str, Any]] = []
        height = self.device.window_size()[1]
        for _ in range(4):
            rows = [
                item
                for item in self._nodes()
                if target
                in [
                    line.strip()
                    for line in item["desc"].splitlines()[:3]
                    if line.strip()
                ]
                and item["top"] > 300
                and item["bottom"] > item["top"]
            ]
            if rows and min(item["top"] for item in rows) < int(height * 0.82):
                break
            if rows:
                # The target exists but is hidden behind the bottom navigation;
                # move list content upward until the row is safely tappable.
                self.device.swipe(600, int(height * 0.82), 600, int(height * 0.45), 0.4)
            else:
                # Recent private chats are normally above older group rows. Move
                # content back toward the list top before declaring it missing.
                self.device.swipe(600, int(height * 0.45), 600, int(height * 0.82), 0.4)
            time.sleep(0.8)
        if not rows:
            raise RuntimeError(f"会话未找到：{target}")
        visible_rows = [item for item in rows if item["top"] < int(height * 0.88)]
        if not visible_rows:
            raise RuntimeError(f"会话仍被底部导航遮挡：{target}")
        row = max(visible_rows, key=lambda item: (item["right"] - item["left"]) * (item["bottom"] - item["top"]))
        self.device.click(max(180, row["left"] + 120), (row["top"] + row["bottom"]) // 2)
        time.sleep(1.5)
        if not self.device(className="android.widget.EditText").exists(timeout=3):
            raise RuntimeError(f"会话输入框未出现：{target}")
        return self.snapshot("chat-opened")

    def visible_outside_edit(self, token: str) -> bool:
        return any(
            token in f"{item['desc']} {item['text']}"
            and item["class"] != "android.widget.EditText"
            and item["package"] == self.package
            for item in self._nodes()
        )

    def send_text(self, text: str, name: str) -> tuple[bool, list[str]]:
        edit = self.device(className="android.widget.EditText")
        if not edit.exists(timeout=3):
            raise RuntimeError("消息输入框缺失")
        edit.click()
        self.device.set_fastinput_ime(True)
        self.device.send_keys(text, clear=True)
        time.sleep(0.4)
        evidence = self.snapshot(f"{name}-typed")
        self.click_send()
        time.sleep(1.4)
        evidence += self.snapshot(f"{name}-sent")
        return self.visible_outside_edit(text), evidence

    def click_send(self) -> None:
        if self.device(description="发送").click_exists(timeout=0.8):
            return
        # The current Flutter build exposes the blue arrow as a clickable NAF
        # node without text/content-desc. Pick the rightmost clickable control
        # in the same vertical band as the chat input.
        edits = [item for item in self._nodes() if item["class"] == "android.widget.EditText"]
        if not edits:
            raise RuntimeError("消息输入框缺失，无法定位发送控件")
        edit = edits[0]
        width, _ = self.device.window_size()
        candidates = [
            item
            for item in self._nodes()
            if item["clickable"]
            and item["left"] > edit["right"]
            and item["left"] > int(width * 0.75)
            and item["top"] < edit["bottom"]
            and item["bottom"] > edit["top"]
        ]
        if not candidates:
            raise RuntimeError("输入文本后未找到发送控件")
        send = max(candidates, key=lambda item: item["right"])
        self.device.click((send["left"] + send["right"]) // 2, (send["top"] + send["bottom"]) // 2)

    def message_bounds(self, token: str) -> tuple[int, int, int, int]:
        width, height = self.device.window_size()
        matches = [
            item
            for item in self._nodes()
            if token in f"{item['desc']} {item['text']}"
            and item["class"] != "android.widget.EditText"
            and item["package"] == self.package
            and item["bottom"] > item["top"]
            and item["top"] < int(height * 0.88)
        ]
        if not matches:
            raise RuntimeError(f"未找到消息气泡：{token}")
        # A replied message can contain the source token inside its quote
        # preview. Prefer a node whose semantics starts with the token so later
        # actions target the original bubble rather than the quoted snapshot.
        direct = [
            item
            for item in matches
            if item["desc"].strip().startswith(token) or item["text"].strip().startswith(token)
        ]
        if direct:
            matches = direct
        # Prefer the smallest direct semantics node that contains the token.
        item = min(
            matches,
            key=lambda row: max(1, row["right"] - row["left"]) * max(1, row["bottom"] - row["top"]),
        )
        left = max(0, min(item["left"], width - 1))
        right = max(left + 1, min(item["right"], width))
        return left, item["top"], right, item["bottom"]

    def open_menu(self, token: str, name: str) -> tuple[list[str], list[str]]:
        labels = (
            "回复",
            "复制",
            "翻译",
            "转发",
            "收藏",
            "消息详情",
            "编辑",
            "撤回",
            "选择",
            "删除",
        )
        for attempt in range(2):
            left, top, right, bottom = self.message_bounds(token)
            self.device.long_click((left + right) // 2, (top + bottom) // 2, duration=0.9)
            time.sleep(1)
            visible = [label for label in labels if self.device(description=label).exists(timeout=0.15)]
            evidence = self.snapshot(f"{name}-menu-{attempt + 1}")
            if visible:
                return visible, evidence
            self.device.press("back")
            time.sleep(0.5)
        raise RuntimeError(f"长按消息后操作菜单未出现：{token}")

    def click_menu(self, label: str) -> None:
        if not self.device(description=label).click_exists(timeout=2):
            raise RuntimeError(f"操作菜单缺少：{label}")
        time.sleep(1)

    def confirm_if_present(self, label: str) -> None:
        candidates = (self.device(text=label), self.device(description=label))
        for candidate in candidates:
            if candidate.exists(timeout=0.5):
                candidate.click()
                time.sleep(1)
                return


def run_copy(batch: MessageActionBatch, cases: dict[str, Case]) -> None:
    token = f"COPY-{datetime.now().strftime('%H%M%S')}"
    sent, evidence = batch.send_text(token, "copy")
    if not sent:
        raise RuntimeError("复制前置消息未发送成功")
    menu, menu_evidence = batch.open_menu(token, "copy")
    batch.click_menu("复制")
    copied = batch.device.clipboard or ""
    after = batch.snapshot("copy-after")
    ok = copied == token
    set_case(
        cases,
        "IM-114",
        "PASS" if ok else "FAIL",
        "发送唯一文本，长按该消息选择“复制”，读取真机系统剪贴板核对。",
        f"剪贴板与原消息完全一致：{token}" if ok else f"复制动作完成，但剪贴板为：{copied!r}",
        evidence + menu_evidence + after,
        "P3",
    )
    batch.record("复制文本", "PASS" if ok else "FAIL", f"menu={menu}, clipboard={copied!r}", evidence + menu_evidence + after)


def run_reply(batch: MessageActionBatch, cases: dict[str, Case]) -> None:
    stamp = datetime.now().strftime("%H%M%S")
    source = f"QUOTE-SRC-{stamp}"
    reply = f"QUOTE-REPLY-{stamp}"
    sent, evidence = batch.send_text(source, "reply-source")
    if not sent:
        raise RuntimeError("回复前置消息未发送成功")
    _, menu_evidence = batch.open_menu(source, "reply")
    batch.click_menu("回复")
    quote_evidence = batch.snapshot("reply-quote-active")
    quote_active = source in batch.device.dump_hierarchy()
    replied, send_evidence = batch.send_text(reply, "reply-result")
    ok = quote_active and replied and batch.visible_outside_edit(source)
    set_case(
        cases,
        "IM-118",
        "PASS" if ok else "FAIL",
        "发送唯一源文本，长按选择“回复”，在引用状态输入另一条唯一文本并发送。",
        "引用条显示源文本，回复消息发送成功，源消息仍保留。" if ok else f"回复结果异常：quote_active={quote_active}, replied={replied}",
        evidence + menu_evidence + quote_evidence + send_evidence,
        "P2",
    )
    batch.record("引用回复", "PASS" if ok else "FAIL", f"quote_active={quote_active}, replied={replied}", evidence + menu_evidence + quote_evidence + send_evidence)


def run_edit(batch: MessageActionBatch, cases: dict[str, Case]) -> None:
    stamp = datetime.now().strftime("%H%M%S")
    original = f"EDIT-OLD-{stamp}"
    edited = f"EDIT-NEW-{stamp}"
    sent, evidence = batch.send_text(original, "edit-original")
    if not sent:
        raise RuntimeError("编辑前置消息未发送成功")
    _, menu_evidence = batch.open_menu(original, "edit")
    batch.click_menu("编辑")
    edit = batch.device(className="android.widget.EditText")
    if not edit.exists(timeout=2):
        raise RuntimeError("点击编辑后输入框未出现")
    input_value = edit.get_text()
    active_evidence = batch.snapshot("edit-active")
    batch.device.set_fastinput_ime(True)
    edit.click()
    batch.device.send_keys(edited, clear=True)
    time.sleep(0.4)
    batch.click_send()
    time.sleep(1.5)
    after = batch.snapshot("edit-after")
    new_visible = batch.visible_outside_edit(edited)
    old_visible = batch.visible_outside_edit(original)
    ok = original in input_value and new_visible and not old_visible
    set_case(
        cases,
        "IM-212",
        "PASS" if ok else "FAIL",
        "发送唯一文本，长按选择“编辑”，替换为另一条唯一文本并提交。",
        "编辑框回填原文；提交后仅显示新文本，原文本不再显示。" if ok else f"编辑结果异常：prefill={input_value!r}, new_visible={new_visible}, old_visible={old_visible}",
        evidence + menu_evidence + active_evidence + after,
        "P2",
    )
    batch.record("编辑消息", "PASS" if ok else "FAIL", f"prefill={input_value!r}, new={new_visible}, old={old_visible}", evidence + menu_evidence + active_evidence + after)


def run_withdraw(batch: MessageActionBatch, cases: dict[str, Case]) -> None:
    token = f"RECALL-{datetime.now().strftime('%H%M%S')}"
    sent, evidence = batch.send_text(token, "recall")
    if not sent:
        raise RuntimeError("撤回前置消息未发送成功")
    _, menu_evidence = batch.open_menu(token, "recall")
    batch.click_menu("撤回")
    batch.confirm_if_present("撤回")
    time.sleep(1)
    after = batch.snapshot("recall-after")
    hierarchy = batch.device.dump_hierarchy()
    token_gone = not batch.visible_outside_edit(token)
    marker = "撤回" in hierarchy
    ok = token_gone and marker
    set_case(
        cases,
        "IM-201",
        "PASS" if ok else "FAIL",
        "发送唯一文本后立即长按选择“撤回”，核对原文本与撤回提示。",
        "原文本消失且会话内出现撤回提示。" if ok else f"撤回结果异常：token_gone={token_gone}, marker={marker}",
        evidence + menu_evidence + after,
        "P2",
    )
    batch.record("时限内撤回", "PASS" if ok else "FAIL", f"token_gone={token_gone}, marker={marker}", evidence + menu_evidence + after)


def run_delete(batch: MessageActionBatch, cases: dict[str, Case]) -> None:
    token = f"DELETE-{datetime.now().strftime('%H%M%S')}"
    sent, evidence = batch.send_text(token, "delete")
    if not sent:
        raise RuntimeError("删除前置消息未发送成功")
    _, menu_evidence = batch.open_menu(token, "delete")
    batch.click_menu("删除")
    batch.confirm_if_present("确认删除")
    time.sleep(1)
    after = batch.snapshot("delete-after")
    gone = not batch.visible_outside_edit(token)
    set_case(
        cases,
        "IM-208",
        "PASS" if gone else "FAIL",
        "发送唯一文本，长按选择“删除”并确认，仅核对本轮新建消息。",
        "目标消息从本机当前会话消失，其他消息保留。" if gone else "删除动作完成后目标文本仍在当前会话显示。",
        evidence + menu_evidence + after,
        "P2",
    )
    batch.record("本地删除单条", "PASS" if gone else "FAIL", f"gone={gone}", evidence + menu_evidence + after)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", required=True)
    parser.add_argument("--run-dir", required=True)
    parser.add_argument("--serial", required=True)
    parser.add_argument("--target", required=True)
    parser.add_argument("--package", default="com.genericim.app")
    parser.add_argument("--only", choices=("all", "copy", "reply", "edit", "withdraw", "delete"), default="all")
    args = parser.parse_args()

    repo = Path(args.repo).resolve()
    run_dir = Path(args.run_dir).resolve()
    evidence_dir = run_dir / f"message-actions-{datetime.now().strftime('%Y%m%d-%H%M%S')}"
    evidence_dir.mkdir(parents=True, exist_ok=True)
    cases, environment, log_summary = load_report(run_dir)
    batch = MessageActionBatch(repo, evidence_dir, args.serial, args.package)
    actions: tuple[tuple[str, Callable[[], None]], ...] = (
        ("copy", lambda: run_copy(batch, cases)),
        ("reply", lambda: run_reply(batch, cases)),
        ("edit", lambda: run_edit(batch, cases)),
        ("withdraw", lambda: run_withdraw(batch, cases)),
        ("delete", lambda: run_delete(batch, cases)),
    )
    if args.only != "all":
        actions = tuple(item for item in actions if item[0] == args.only)

    try:
        open_evidence = batch.open_chat(args.target)
        batch.record("进入目标会话", "PASS", args.target, open_evidence)
        for name, action in actions:
            try:
                action()
            except Exception as exc:
                evidence = batch.snapshot(f"{name}-harness-error")
                batch.record(name, "BLOCKED", f"自动化步骤异常：{type(exc).__name__}: {exc}", evidence)
                # Recover from transient sheets/keyboards before the next action.
                for _ in range(2):
                    if batch.device(className="android.widget.EditText").exists(timeout=0.5):
                        break
                    batch.device.press("back")
                    time.sleep(0.5)
            write_report(repo, run_dir, cases, environment, log_summary)
    finally:
        try:
            batch.device.set_fastinput_ime(False)
        except Exception:
            pass

    print(f"[MSG400] report={run_dir / 'IM_400_FULL_REAL_DEVICE_TEST_REPORT.md'}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
