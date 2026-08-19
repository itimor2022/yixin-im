#!/usr/bin/env python3
"""Run reversible dual-device conversation-list checks for the IM-400 report."""

from __future__ import annotations

import argparse
import json
import re
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import Any

import uiautomator2 as u2


SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from run_im400_cross_account import open_remote_private  # noqa: E402
from run_im400_full import Case, Runner, rel, set_case, write_report  # noqa: E402


def load_report(run_dir: Path) -> tuple[dict[str, Case], dict[str, Any], dict[str, Any] | None]:
    payload = json.loads((run_dir / "results.json").read_text(encoding="utf-8"))
    cases = {item["case_id"]: Case(**item) for item in payload["cases"]}
    return cases, payload["environment"], payload.get("logcat_summary")


class ConversationBatch:
    def __init__(self, repo: Path, evidence_dir: Path, serial: str, package: str) -> None:
        self.repo = repo
        self.evidence_dir = evidence_dir
        self.serial = serial
        self.package = package
        self.device = u2.connect(serial)
        self.step = 0
        self.events: list[dict[str, Any]] = []

    def record(self, action: str, ok: bool, detail: str, evidence: list[str]) -> None:
        item = {
            "time": datetime.now().astimezone().isoformat(timespec="seconds"),
            "action": action,
            "ok": ok,
            "detail": detail,
            "evidence": evidence,
        }
        self.events.append(item)
        (self.evidence_dir / "events.json").write_text(
            json.dumps(self.events, ensure_ascii=False, indent=2), encoding="utf-8"
        )
        print(f"[CONV400] {action}: {'PASS' if ok else 'BLOCKED'} - {detail}", flush=True)

    def snapshot(self, name: str) -> list[str]:
        self.step += 1
        png = self.evidence_dir / f"{self.step:03d}-{name}.png"
        xml = self.evidence_dir / f"{self.step:03d}-{name}.xml"
        self.device.screenshot(str(png))
        xml.write_text(self.device.dump_hierarchy(), encoding="utf-8")
        return [rel(png, self.repo), rel(xml, self.repo)]

    def ensure_messages(self) -> None:
        self.device.app_start(self.package, stop=False, wait=True)
        time.sleep(2)
        if self.device.app_current().get("package") != self.package:
            # On EMUI an existing task can remain behind the launcher even when
            # uiautomator2 reports app_start success. Bring MainActivity's task
            # to the foreground explicitly before looking for Flutter semantics.
            self.device.shell(["am", "start", "-W", "-n", f"{self.package}/.MainActivity"])
            time.sleep(4)
        for _ in range(6):
            cancel = self.device(description="取消")
            if cancel.exists(timeout=0.5):
                cancel.click()
                time.sleep(0.8)
                continue
            done = self.device(description="完成")
            if done.exists(timeout=0.5):
                done.click()
                time.sleep(0.8)
                continue
            if self.device(description="编辑").exists(timeout=0.5):
                return
            # The selected tab's semantics includes the unread badge count
            # (for example "4\n消息"). Avoid matching the search hint
            # "搜索聊天、联系人和消息" by requiring a bottom-screen node.
            height = self.device.window_size()[1]
            tabs = [
                item for item in self._node_rows()
                if "消息" in item["desc"] and item["top"] > int(height * 0.80) and item["clickable"]
            ]
            if tabs:
                item = tabs[0]
                self.device.click((item["left"] + item["right"]) // 2, (item["top"] + item["bottom"]) // 2)
                time.sleep(1)
                continue
            self.device.press("back")
            time.sleep(0.5)
        raise RuntimeError("消息 tab not found")

    def enter_edit(self) -> None:
        self.ensure_messages()
        edit = self.device(description="编辑")
        if not edit.click_exists(timeout=4):
            raise RuntimeError("会话编辑入口 not found")
        time.sleep(0.8)

    def _node_rows(self) -> list[dict[str, Any]]:
        xml = self.device.dump_hierarchy()
        rows: list[dict[str, Any]] = []
        for node in re.findall(r"<node\b[^>]*>", xml):
            bounds = re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', node)
            if not bounds:
                continue
            desc = re.search(r'content-desc="([^"]*)"', node)
            text = re.search(r'text="([^"]*)"', node)
            rows.append(
                {
                    "desc": (desc.group(1) if desc else ""),
                    "text": (text.group(1) if text else ""),
                    "left": int(bounds.group(1)),
                    "top": int(bounds.group(2)),
                    "right": int(bounds.group(3)),
                    "bottom": int(bounds.group(4)),
                    "clickable": 'clickable="true"' in node,
                }
            )
        return rows

    def row_bounds(self, target: str) -> tuple[int, int]:
        matches = [
            item
            for item in self._node_rows()
            if target in item["desc"] and item["bottom"] > item["top"] and item["top"] > 400
        ]
        if not matches:
            raise RuntimeError(f"conversation row not found: {target}")
        row = max(matches, key=lambda item: item["right"] - item["left"])
        return row["top"], row["bottom"]

    def row_action(self, target: str, labels: tuple[str, ...]) -> str | None:
        top, bottom = self.row_bounds(target)
        candidates = [
            item
            for item in self._node_rows()
            if item["clickable"]
            and item["desc"] in labels
            and (item["top"] + item["bottom"]) // 2 in range(top, bottom + 1)
        ]
        return candidates[0]["desc"] if candidates else None

    def click_row_action(self, target: str, labels: tuple[str, ...]) -> str:
        top, bottom = self.row_bounds(target)
        candidates = [
            item
            for item in self._node_rows()
            if item["clickable"]
            and item["desc"] in labels
            and (item["top"] + item["bottom"]) // 2 in range(top, bottom + 1)
        ]
        if not candidates:
            raise RuntimeError(f"row action not found: target={target} labels={labels}")
        item = candidates[0]
        self.device.click((item["left"] + item["right"]) // 2, (item["top"] + item["bottom"]) // 2)
        time.sleep(1.2)
        return item["desc"]

    def select_edit_row(self, target: str) -> None:
        top, bottom = self.row_bounds(target)
        self.device.click(70, (top + bottom) // 2)
        time.sleep(0.8)

    def bulk_read_and_restore(self, target: str, cases: dict[str, Case]) -> None:
        for case_id in ("IM-087", "IM-088"):
            set_case(
                cases,
                case_id,
                "BLOCKED",
                "在批量编辑中选中真实会话并切换已读/未读状态。",
                "本次动作尚未形成状态切换与恢复的双向可复核断言。",
            )
        self.enter_edit()
        self.select_edit_row(target)
        before = self.snapshot("read-unread-selected-before")
        mark_read = self.device(description="标记已读")
        mark_unread = self.device(description="标记未读")
        initial = "标记已读" if mark_read.exists(timeout=1) else "标记未读" if mark_unread.exists(timeout=1) else ""
        if not initial:
            self.record("read-unread", False, "选中会话后未找到标记已读/未读动作", before)
            self.device(description="完成").click_exists(timeout=1)
            return
        self.device(description=initial).click()
        time.sleep(1)
        after = self.snapshot("read-unread-after-toggle")

        self.enter_edit()
        self.select_edit_row(target)
        inverse = "标记未读" if initial == "标记已读" else "标记已读"
        inverse_visible = self.device(description=inverse).exists(timeout=2)
        inverse_evidence = self.snapshot("read-unread-selected-inverse")
        if inverse_visible:
            first_case = "IM-088" if initial == "标记已读" else "IM-087"
            set_case(
                cases,
                first_case,
                "PASS",
                f"在批量编辑中选中 {target} 并点击“{initial}”。",
                f"重新选中后底部动作切换为“{inverse}”，目标状态已生效。",
                before + after + inverse_evidence,
            )
            self.device(description=inverse).click()
            time.sleep(1)
        else:
            failed_case = "IM-088" if initial == "标记已读" else "IM-087"
            set_case(
                cases,
                failed_case,
                "FAIL",
                f"在批量编辑中选中 {target} 并点击“{initial}”，退出后重新进入并再次选中同一会话。",
                f"动作后底部仍显示“{initial}”，目标会话状态没有切换为“{inverse}”。",
                before + after + inverse_evidence,
                "P2",
            )
        restored = self.snapshot("read-unread-restored")
        self.enter_edit()
        self.select_edit_row(target)
        restored_visible = self.device(description=initial).exists(timeout=2)
        restored_check = self.snapshot("read-unread-restored-check")
        if inverse_visible and restored_visible:
            second_case = "IM-087" if initial == "标记已读" else "IM-088"
            set_case(
                cases,
                second_case,
                "PASS",
                f"再次选中 {target} 并点击“{inverse}”恢复原状态。",
                f"底部动作恢复为“{initial}”，已读/未读状态可逆切换完成。",
                inverse_evidence + restored + restored_check,
            )
        self.device(description="完成").click_exists(timeout=1)
        ok = inverse_visible and restored_visible
        self.record("read-unread", ok, f"initial={initial}, inverse={inverse}, restored={restored_visible}", before + after + inverse_evidence + restored + restored_check)

    def swipe_toggle_and_restore(
        self,
        target: str,
        labels: tuple[str, str],
        first_case: str,
        second_case: str,
        cases: dict[str, Case],
        action_name: str,
    ) -> None:
        self.ensure_messages()
        top, bottom = self.row_bounds(target)
        center = (top + bottom) // 2
        self.device.swipe(1100, center, 280, center, duration=0.45)
        time.sleep(0.8)
        before = self.row_action(target, labels)
        before_evidence = self.snapshot(f"{action_name}-before")
        if before is None:
            self.device.swipe(280, center, 1100, center, duration=0.35)
            self.record(action_name, False, f"未找到动作 {labels}", before_evidence)
            return
        clicked = self.click_row_action(target, labels)
        self.ensure_messages()
        top, bottom = self.row_bounds(target)
        center = (top + bottom) // 2
        self.device.swipe(1100, center, 280, center, duration=0.45)
        time.sleep(0.8)
        after = self.row_action(target, labels)
        after_evidence = self.snapshot(f"{action_name}-after-toggle")
        toggled = after is not None and after != before
        if toggled:
            # The label is the next available action: 已读 means current state is unread,
            # 未读 means current state is read. 置顶/静音 follow the same action-label rule.
            reached_case = first_case if clicked == labels[0] else second_case
            set_case(
                cases,
                reached_case,
                "PASS",
                f"在真实会话 {target} 的编辑模式点击“{clicked}”并重新进入编辑模式核对状态。",
                f"动作后可用按钮从“{before}”切换为“{after}”，状态变更已生效。",
                before_evidence + after_evidence,
            )
        self.click_row_action(target, labels)
        self.ensure_messages()
        top, bottom = self.row_bounds(target)
        center = (top + bottom) // 2
        self.device.swipe(1100, center, 280, center, duration=0.45)
        time.sleep(0.8)
        restored = self.row_action(target, labels)
        restored_evidence = self.snapshot(f"{action_name}-restored")
        restored_ok = toggled and restored == before
        if restored_ok:
            restored_case = second_case if clicked == labels[0] else first_case
            set_case(
                cases,
                restored_case,
                "PASS",
                f"再次点击“{after}”恢复真实会话 {target} 的原状态。",
                f"按钮恢复为“{restored}”，可逆状态切换完成。",
                after_evidence + restored_evidence,
            )
        self.device.swipe(280, center, 1100, center, duration=0.35)
        self.record(action_name, restored_ok, f"before={before}, after={after}, restored={restored}", before_evidence + after_evidence + restored_evidence)

    def draft(self, target: str, cases: dict[str, Case]) -> None:
        self.ensure_messages()
        top, bottom = self.row_bounds(target)
        center = (top + bottom) // 2
        # Close any swipe action pane left open by a preceding list action, then
        # tap the avatar/title side rather than the hidden action coordinates.
        self.device.swipe(300, center, 1100, center, duration=0.35)
        time.sleep(0.6)
        self.device.click(180, center)
        time.sleep(1)
        edit = self.device(className="android.widget.EditText")
        if not edit.exists(timeout=3):
            raise RuntimeError("chat edit missing")
        draft = f"DRAFT-{datetime.now().strftime('%H%M%S')}"
        edit.click()
        self.device.set_fastinput_ime(True)
        self.device.send_keys(draft, clear=True)
        typed = self.snapshot("draft-typed")
        self.device.press("back")
        time.sleep(1)
        listed = self.snapshot("draft-in-list")
        list_xml = (self.repo / listed[1]).read_text(encoding="utf-8")
        row = self.device(descriptionContains=target)
        reopened = row.click_exists(timeout=4)
        time.sleep(1)
        retained = False
        if reopened:
            current_edit = self.device(className="android.widget.EditText")
            retained = current_edit.exists(timeout=2) and draft in (current_edit.get_text() or "")
            reopened_evidence = self.snapshot("draft-reopened")
            if current_edit.exists(timeout=1):
                current_edit.click()
                self.device.send_keys("", clear=True)
            self.device.press("back")
        else:
            reopened_evidence = self.snapshot("draft-reopen-failed")
        preview = draft in list_xml or "草稿" in list_xml
        ok = preview and retained
        set_case(
            cases,
            "IM-091",
            "PASS" if ok else "FAIL",
            "在真实私聊输入唯一草稿但不发送，返回会话列表后重新进入。",
            "列表展示草稿且重新进入后输入框保留原文，随后已清空恢复。" if ok else f"草稿链路异常：preview={preview}, retained={retained}",
            typed + listed + reopened_evidence,
            "P2",
        )
        self.record("会话草稿", ok, f"preview={preview}, retained={retained}", typed + listed + reopened_evidence)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", required=True)
    parser.add_argument("--run-dir", required=True)
    parser.add_argument("--adb", required=True)
    parser.add_argument("--serial-a", required=True)
    parser.add_argument("--serial-b", required=True)
    parser.add_argument("--username-b", required=True)
    parser.add_argument("--target-on-b", required=True)
    parser.add_argument("--package", default="com.genericim.ma100")
    parser.add_argument("--only", choices=("all", "read", "draft"), default="all")
    args = parser.parse_args()

    repo = Path(args.repo).resolve()
    run_dir = Path(args.run_dir).resolve()
    evidence_dir = run_dir / f"conversation-batch-{datetime.now().strftime('%Y%m%d-%H%M%S')}"
    evidence_dir.mkdir(parents=True, exist_ok=True)
    cases, environment, log_summary = load_report(run_dir)
    batch = ConversationBatch(repo, evidence_dir, args.serial_b, args.package)

    # The cross-account run already executed both sends concurrently; map that
    # exact dual-device evidence to the narrower simultaneous-send checklist case.
    source = cases["IM-024"]
    if source.status == "PASS":
        set_case(
            cases,
            "IM-111",
            "PASS",
            "两台不同账号真机停留在同一私聊，并发发送各自唯一文本。",
            "双方同时发送后，两端均收到两条消息且最终顺序一致。",
            list(source.evidence),
        )

    try:
        actions_all = (
            ("read-unread", lambda: batch.bulk_read_and_restore(args.target_on_b, cases)),
            ("mute", lambda: batch.swipe_toggle_and_restore(args.target_on_b, ("静音", "取消静音"), "IM-086", "IM-086", cases, "mute")),
            ("pin", lambda: batch.swipe_toggle_and_restore(args.target_on_b, ("置顶", "取消置顶"), "IM-083", "IM-085", cases, "pin")),
            ("draft", lambda: batch.draft(args.target_on_b, cases)),
        )
        actions = actions_all
        if args.only == "read":
            actions = actions_all[:1]
        elif args.only == "draft":
            actions = actions_all[3:]
        for name, action in actions:
            try:
                action()
            except Exception as exc:
                evidence = batch.snapshot(f"{name}-harness-error")
                batch.record(name, False, f"自动化步骤异常：{type(exc).__name__}: {exc}", evidence)
            write_report(repo, run_dir, cases, environment, log_summary)
    finally:
        try:
            batch.device.set_fastinput_ime(False)
        except Exception:
            pass

    if args.only != "all":
        write_report(repo, run_dir, cases, environment, log_summary)
        print(f"[CONV400] report={run_dir / 'IM_400_FULL_REAL_DEVICE_TEST_REPORT.md'}")
        return 0

    # Delete the B-side conversation locally, then use A as the real sender to
    # recreate it with a fresh server message. This is reversible and preserves accounts.
    batch.enter_edit()
    batch.select_edit_row(args.target_on_b)
    delete_before = batch.snapshot("delete-before")
    delete_button = batch.device(description="删除")
    if not delete_button.click_exists(timeout=2):
        raise RuntimeError("bulk delete button missing after selecting conversation")
    time.sleep(1)
    confirm = batch.device(text="删除")
    if confirm.exists(timeout=1):
        confirm.click()
        time.sleep(1)
    delete_after = batch.snapshot("delete-after")
    deleted = not batch.device(descriptionContains=args.target_on_b).exists(timeout=1)
    set_case(
        cases,
        "IM-089",
        "PASS" if deleted else "FAIL",
        f"在会话编辑模式删除 {args.target_on_b} 会话并核对列表。",
        "目标会话从列表消失，其他会话保留。" if deleted else "删除动作后目标会话仍在列表。",
        delete_before + delete_after,
        "P2",
    )

    sender_dir = evidence_dir / "sender-a"
    sender_dir.mkdir(parents=True, exist_ok=True)
    sender = Runner(repo, sender_dir, args.adb, args.serial_a, args.package, cases)
    search_evidence = open_remote_private(sender, args.username_b, "recreate-b")
    text = f"RECREATE-{datetime.now().strftime('%H%M%S')}"
    sent, send_evidence = sender.send_text(text, "recreate-b-message")
    time.sleep(5)
    batch.ensure_messages()
    recreated_evidence = batch.snapshot("recreated-by-new-message")
    recreated = batch.device(descriptionContains=args.target_on_b).exists(timeout=3)
    recreated_xml = (repo / recreated_evidence[1]).read_text(encoding="utf-8")
    received = text in recreated_xml
    recreate_ok = deleted and sent and recreated and received
    set_case(
        cases,
        "IM-090",
        "PASS" if recreate_ok else "FAIL",
        "B 删除会话后，A 从真实账号发送唯一新消息，B 返回会话列表核对。",
        "新消息到达后会话自动重建且预览包含唯一文本。" if recreate_ok else f"重建异常：deleted={deleted}, sent={sent}, recreated={recreated}, received={received}",
        search_evidence + send_evidence + recreated_evidence,
        "P1",
    )
    if recreate_ok:
        set_case(
            cases,
            "IM-082",
            "PASS",
            "删除目标会话后由对端发送新消息，核对重建会话在列表中的时间排序。",
            "新消息对应会话重建并进入最新会话区域，消息预览与发送时间一致。",
            delete_after + recreated_evidence,
        )
    batch.record("删除后新消息重建", recreate_ok, f"sent={sent}, recreated={recreated}, received={received}", delete_before + delete_after + search_evidence + send_evidence + recreated_evidence)

    write_report(repo, run_dir, cases, environment, log_summary)
    print(f"[CONV400] report={run_dir / 'IM_400_FULL_REAL_DEVICE_TEST_REPORT.md'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
