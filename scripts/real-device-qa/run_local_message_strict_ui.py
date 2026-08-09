#!/usr/bin/env python3
"""Strict local-Docker UI checks for remaining message contracts on two devices."""

from __future__ import annotations

import argparse
import json
import sys
import time
import urllib.parse
from datetime import datetime
from pathlib import Path
from typing import Any


SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from prepare_dual_device_apk import login_device, run_adb  # noqa: E402
from run_im400_message_actions import MessageActionBatch  # noqa: E402
from run_im400_remaining_api import (  # noqa: E402
    Actor,
    Api,
    create_chat,
    get_messages,
    list_items,
    response_data,
    send_text,
)
from run_local_group_realtime_real_device import login  # noqa: E402


def contains_token(value: Any, token: str) -> bool:
    return token in json.dumps(value, ensure_ascii=False, sort_keys=True)


def wait_until(predicate, timeout: int = 20, interval: float = 1.0) -> bool:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if predicate():
            return True
        time.sleep(interval)
    return False


class StrictMessageUi:
    def __init__(self, args: argparse.Namespace, run_dir: Path) -> None:
        self.args = args
        self.repo = Path(args.repo).resolve()
        self.run_dir = run_dir
        self.a_dir = run_dir / "alice"
        self.b_dir = run_dir / "bob"
        self.a_dir.mkdir(parents=True, exist_ok=True)
        self.b_dir.mkdir(parents=True, exist_ok=True)
        self.api = Api(args.base.rstrip("/"))
        self.alice = login(self.api, "smoke_alice", args.password, "alice-message-ui")
        self.bob = login(self.api, "smoke_bob", args.password, "bob-message-ui")
        self.a = MessageActionBatch(self.repo, self.a_dir, args.alice, args.package)
        self.b = MessageActionBatch(self.repo, self.b_dir, args.bob, args.package)
        self.source_group_id = ""
        self.target_group_id = ""
        self.source_group_name = ""
        self.target_group_name = ""
        self.private_chat_id = ""
        self.result: dict[str, Any] = {
            "status": "FAIL",
            "base": args.base,
            "devices": {"alice": args.alice, "bob": args.bob},
            "cases": {},
            "evidence_dir": str(run_dir),
        }

    def record(self, case_id: str, status: str, checks: dict[str, Any]) -> None:
        self.result["cases"][case_id] = {"status": status, "checks": checks}
        (self.run_dir / "case-result.json").write_text(
            json.dumps(self.result, ensure_ascii=False, indent=2), encoding="utf-8"
        )
        print(f"[LOCAL-MSG-UI] {case_id}: {status} {checks}", flush=True)

    def cleanup_old_groups(self) -> None:
        chats = list_items(
            self.api.request("GET", "/chat/list?page=1&page_size=100", actor=self.alice)
        )
        for chat in chats:
            name = str(chat.get("name") or chat.get("chat_name") or "")
            chat_id = str(chat.get("chat_id") or chat.get("uuid") or "")
            if name.startswith("LOCAL_MSG_UI_") and chat_id:
                try:
                    self.api.request("DELETE", f"/chat/{chat_id}", actor=self.alice)
                except Exception:
                    pass

    def setup(self) -> None:
        self.cleanup_old_groups()
        stamp = datetime.now().strftime("%H%M%S")
        self.source_group_name = f"LOCAL_MSG_UI_SRC_{stamp}"
        self.target_group_name = f"LOCAL_MSG_UI_DST_{stamp}"
        self.source_group_id = create_chat(
            self.api, self.alice, 2, [self.bob], self.source_group_name
        )
        self.target_group_id = create_chat(
            self.api, self.alice, 2, [self.bob], self.target_group_name
        )
        self.private_chat_id = create_chat(self.api, self.alice, 1, [self.bob])
        send_text(
            self.api,
            self.alice,
            self.source_group_id,
            f"SOURCE_READY_{stamp}",
        )
        send_text(
            self.api,
            self.alice,
            self.target_group_id,
            f"TARGET_READY_{stamp}",
        )
        self.result.update(
            {
                "source_group": {
                    "id": self.source_group_id,
                    "name": self.source_group_name,
                },
                "target_group": {
                    "id": self.target_group_id,
                    "name": self.target_group_name,
                },
                "private_chat_id": self.private_chat_id,
            }
        )
        for batch in (self.a, self.b):
            batch.device.app_start(self.args.package, stop=True, wait=True)
        time.sleep(6)
        self.a.ensure_messages()
        self.b.ensure_messages()

    def click_target(self, batch: MessageActionBatch, target: str) -> None:
        matches: list[dict[str, Any]] = []
        height = batch.device.window_size()[1]
        for _ in range(20):
            matches = [
                item
                for item in batch._nodes()
                if item["clickable"]
                and item["class"] == "android.widget.Button"
                and item["bottom"] < int(height * 0.93)
                and target in [line.strip() for line in item["desc"].splitlines()]
            ]
            if matches:
                break
            batch.device.swipe(600, int(height * 0.82), 600, int(height * 0.46), 0.45)
            time.sleep(0.5)
        if not matches:
            raise RuntimeError(f"forward target not found: {target}")
        item = max(
            matches,
            key=lambda row: (row["right"] - row["left"])
            * (row["bottom"] - row["top"]),
        )
        batch.device.click(
            (item["left"] + item["right"]) // 2,
            (item["top"] + item["bottom"]) // 2,
        )
        time.sleep(0.8)

    def select_messages(
        self, batch: MessageActionBatch, first: str, second: str, label: str
    ) -> list[str]:
        batch.open_chat(self.source_group_name)
        if not batch.visible_outside_edit(first) or not batch.visible_outside_edit(second):
            raise RuntimeError(f"source messages are not visible: {first}, {second}")
        _, evidence = batch.open_menu(first, f"{label}-first")
        batch.click_menu("选择")
        time.sleep(0.8)
        left, top, right, bottom = batch.message_bounds(second)
        batch.device.click((left + right) // 2, (top + bottom) // 2)
        if not wait_until(
            lambda: "已选择 2 条消息" in batch.device.dump_hierarchy(), timeout=5
        ):
            raise RuntimeError("selection mode did not report two messages")
        evidence += batch.snapshot(f"{label}-selected-two")
        return evidence

    def forward_selected(
        self,
        batch: MessageActionBatch,
        mode: str,
        targets: list[str],
        label: str,
    ) -> list[str]:
        if not batch.device(description="转发").click_exists(timeout=2):
            raise RuntimeError("selection forward button missing")
        time.sleep(0.8)
        mode_label = "逐条转发" if mode == "separate" else "合并转发"
        if not batch.device(descriptionContains=mode_label).click_exists(timeout=2):
            raise RuntimeError(f"forward mode missing: {mode_label}")
        time.sleep(1.2)
        evidence = batch.snapshot(f"{label}-target-picker")
        for target in targets:
            self.click_target(batch, target)
        evidence += batch.snapshot(f"{label}-targets-selected")
        submit = batch.device(description=f"转发到 {len(targets)} 个会话")
        if not submit.click_exists(timeout=2):
            raise RuntimeError("forward submit button missing")
        time.sleep(9)
        evidence += batch.snapshot(f"{label}-submitted")
        return evidence

    def send_pair(self, prefix: str) -> tuple[str, str, list[str]]:
        self.a.open_chat(self.source_group_name)
        first = f"{prefix}_A_{datetime.now().strftime('%H%M%S')}"
        second = f"{prefix}_B_{datetime.now().strftime('%H%M%S')}"
        ok_first, evidence = self.a.send_text(first, f"{prefix.lower()}-a")
        ok_second, second_evidence = self.a.send_text(second, f"{prefix.lower()}-b")
        if not ok_first or not ok_second:
            raise RuntimeError(f"failed to send source pair: {prefix}")
        return first, second, evidence + second_evidence

    def matching_messages(
        self, actor: Actor, chat_id: str, tokens: list[str]
    ) -> list[dict[str, Any]]:
        return [
            item
            for item in get_messages(self.api, actor, chat_id)
            if any(contains_token(item, token) for token in tokens)
        ]

    def verify_separate_target(
        self, actor: Actor, chat_id: str, tokens: list[str]
    ) -> tuple[bool, list[int]]:
        messages = self.matching_messages(actor, chat_id, tokens)
        counts = [sum(contains_token(item, token) for item in messages) for token in tokens]
        seqs: list[int] = []
        for token in tokens:
            match = next((item for item in messages if contains_token(item, token)), None)
            seqs.append(int(match.get("seq", 0)) if match else 0)
        return counts == [1, 1] and seqs[0] < seqs[1], seqs

    def case_forward_separate_multi_target(self) -> None:
        first, second, send_evidence = self.send_pair("IM215216")
        select_evidence = self.select_messages(self.a, first, second, "im215216")
        forward_evidence = self.forward_selected(
            self.a,
            "separate",
            [self.target_group_name, "Smoke Bob"],
            "im215216",
        )
        private_ok = wait_until(
            lambda: self.verify_separate_target(
                self.bob, self.private_chat_id, [first, second]
            )[0]
        )
        target_ok = wait_until(
            lambda: self.verify_separate_target(
                self.bob, self.target_group_id, [first, second]
            )[0]
        )
        private_seqs = self.verify_separate_target(
            self.bob, self.private_chat_id, [first, second]
        )[1]
        target_seqs = self.verify_separate_target(
            self.bob, self.target_group_id, [first, second]
        )[1]

        private_ui_evidence = self.b.open_chat("Smoke Alice")
        private_ui = self.b.visible_outside_edit(first) and self.b.visible_outside_edit(
            second
        )
        private_ui_evidence += self.b.snapshot("im215216-private-target")
        group_ui_evidence = self.b.open_chat(self.target_group_name)
        group_ui = self.b.visible_outside_edit(first) and self.b.visible_outside_edit(second)
        group_ui_evidence += self.b.snapshot("im215216-group-target")

        common = {
            "tokens": [first, second],
            "private_api_once_in_order": private_ok,
            "group_api_once_in_order": target_ok,
            "private_sequences": private_seqs,
            "group_sequences": target_seqs,
            "private_ui_visible": private_ui,
            "group_ui_visible": group_ui,
            "evidence": send_evidence
            + select_evidence
            + forward_evidence
            + private_ui_evidence
            + group_ui_evidence,
        }
        self.record(
            "IM-215",
            "PASS" if private_ok and private_ui else "FAIL",
            common,
        )
        self.record(
            "IM-216",
            "PASS" if private_ok and target_ok and private_ui and group_ui else "FAIL",
            common,
        )

    def case_forward_bundle(self) -> None:
        first, second, send_evidence = self.send_pair("IM199")
        select_evidence = self.select_messages(self.a, first, second, "im199")
        forward_evidence = self.forward_selected(
            self.a, "bundle", ["Smoke Bob"], "im199"
        )

        def bundle_messages() -> list[dict[str, Any]]:
            return [
                item
                for item in get_messages(self.api, self.bob, self.private_chat_id)
                if int(item.get("type", 0)) == 14
                and contains_token(item, first)
                and contains_token(item, second)
            ]

        bundle_api = wait_until(lambda: len(bundle_messages()) == 1)
        api_items = bundle_messages()
        api_order = bool(api_items) and json.dumps(
            api_items[0], ensure_ascii=False
        ).find(first) < json.dumps(api_items[0], ensure_ascii=False).find(second)

        ui_evidence = self.b.open_chat("Smoke Alice")
        xml = self.b.device.dump_hierarchy()
        bundle_nodes = [
            item
            for item in self.b._nodes()
            if item["clickable"]
            and "聊天记录" in item["desc"]
            and first in item["desc"]
            and second in item["desc"]
        ]
        if not bundle_nodes:
            raise RuntimeError("forward bundle bubble did not appear on Bob")
        node = max(
            bundle_nodes,
            key=lambda row: (row["right"] - row["left"])
            * (row["bottom"] - row["top"]),
        )
        self.b.device.click(
            (node["left"] + node["right"]) // 2,
            (node["top"] + node["bottom"]) // 2,
        )
        time.sleep(2)
        ui_evidence += self.b.snapshot("im199-bundle-preview")
        preview = self.b.device.dump_hierarchy()
        ui_order = first in preview and second in preview and preview.find(first) < preview.find(second)
        self.b.device.press("back")
        checks = {
            "tokens": [first, second],
            "single_authoritative_bundle": bundle_api,
            "api_snapshot_order": api_order,
            "bundle_ui_openable_and_ordered": ui_order,
            "evidence": send_evidence + select_evidence + forward_evidence + ui_evidence,
        }
        self.record(
            "IM-199",
            "PASS" if bundle_api and api_order and ui_order else "FAIL",
            checks,
        )

    def open_message_detail(
        self, batch: MessageActionBatch, chat_name: str, token: str, label: str
    ) -> tuple[str, list[str]]:
        evidence = batch.open_chat(chat_name)
        _, menu_evidence = batch.open_menu(token, label)
        batch.click_menu("消息详情")
        time.sleep(3)
        evidence += menu_evidence + batch.snapshot(f"{label}-detail")
        xml = batch.device.dump_hierarchy()
        batch.device.press("back")
        time.sleep(0.8)
        return xml, evidence

    def case_message_detail(self) -> None:
        private_messages = get_messages(self.api, self.bob, self.private_chat_id)
        private_source = next(
            (
                item
                for item in private_messages
                if int(item.get("type", 0)) == 1
                and isinstance(item.get("content"), dict)
                and item["content"].get("text")
            ),
            None,
        )
        if not private_source:
            raise RuntimeError("private detail source message missing")
        private_token = str(private_source["content"]["text"])
        private_xml, private_evidence = self.open_message_detail(
            self.b, "Smoke Alice", private_token, "im220-private"
        )

        group_token = f"IM220_GROUP_{datetime.now().strftime('%H%M%S')}"
        send_text(self.api, self.alice, self.source_group_id, group_token)
        self.b.open_chat(self.source_group_name)
        if not wait_until(lambda: self.b.visible_outside_edit(group_token)):
            raise RuntimeError("group detail source message did not reach Bob")
        group_xml, group_evidence = self.open_message_detail(
            self.b, self.source_group_name, group_token, "im220-group"
        )
        private_loaded = all(
            marker in private_xml for marker in ("消息详情", "发送时间", "消息状态", "消息序号")
        ) and "服务器详情暂不可用" not in private_xml
        group_loaded = all(
            marker in group_xml
            for marker in ("消息详情", "接收人数", "已读", "未读", "已送达")
        ) and "服务器详情暂不可用" not in group_xml
        privacy = "为保护成员隐私，你只能查看汇总数据" in group_xml and "成员状态" not in group_xml
        checks = {
            "private_authoritative_detail": private_loaded,
            "group_authoritative_summary": group_loaded,
            "ordinary_member_privacy_enforced": privacy,
            "evidence": private_evidence + group_evidence,
        }
        self.record(
            "IM-220",
            "PASS" if private_loaded and group_loaded and privacy else "FAIL",
            checks,
        )

    def open_favorites(
        self, batch: MessageActionBatch, chat_name: str, label: str
    ) -> list[str]:
        batch.device.app_start(self.args.package, wait=True)
        for action_label in ("我知道了", "知道了"):
            if batch.device(description=action_label).click_exists(timeout=1):
                time.sleep(1)
                break
            if batch.device(text=action_label).click_exists(timeout=1):
                time.sleep(1)
                break
        evidence = batch.open_chat(chat_name)
        width, height = batch.device.window_size()
        entries = [
            item
            for item in batch._nodes()
            if item["clickable"]
            and item["class"]
            not in ("android.widget.EditText", "android.widget.ImageView")
            and item["left"] < int(width * 0.2)
            and item["top"] > int(height * 0.88)
        ]
        if not entries:
            raise RuntimeError("attachment entry missing")
        entry = min(entries, key=lambda row: row["top"])
        batch.device.click(
            (entry["left"] + entry["right"]) // 2,
            (entry["top"] + entry["bottom"]) // 2,
        )
        time.sleep(1)
        if not batch.device(description="收藏").click_exists(timeout=2):
            raise RuntimeError("favorites attachment action missing")
        time.sleep(3)
        evidence += batch.snapshot(f"{label}-favorites")
        return evidence

    def remove_favorite(
        self, batch: MessageActionBatch, token: str, label: str
    ) -> list[str]:
        token_nodes = [item for item in batch._nodes() if token in item["desc"]]
        if not token_nodes:
            raise RuntimeError("favorite token missing before removal")
        token_node = max(
            token_nodes,
            key=lambda row: (row["right"] - row["left"])
            * (row["bottom"] - row["top"]),
        )
        deletes = [
            item
            for item in batch._nodes()
            if item["desc"] == "删除收藏"
            and item["top"] < token_node["bottom"]
            and item["bottom"] > token_node["top"]
        ]
        if not deletes:
            raise RuntimeError("matching delete favorite action missing")
        item = deletes[0]
        batch.device.click(
            (item["left"] + item["right"]) // 2,
            (item["top"] + item["bottom"]) // 2,
        )
        time.sleep(0.8)
        evidence = batch.snapshot(f"{label}-remove-confirm")
        if not batch.device(description="删除").click_exists(timeout=2):
            raise RuntimeError("delete favorite confirmation missing")
        time.sleep(3)
        evidence += batch.snapshot(f"{label}-removed")
        return evidence

    def switch_bob_account(self, username: str, label: str) -> MessageActionBatch:
        run_adb(
            self.args.adb,
            self.args.bob,
            "shell",
            "pm",
            "clear",
            self.args.package,
        )
        login_device(
            self.args.adb,
            self.args.bob,
            username,
            self.args.password,
            self.args.package,
            self.run_dir / f"bob-login-{label}",
        )
        evidence_dir = self.run_dir / f"bob-{label}"
        evidence_dir.mkdir(parents=True, exist_ok=True)
        return MessageActionBatch(
            self.repo, evidence_dir, self.args.bob, self.args.package
        )

    def case_favorite_sync(self) -> None:
        token = f"IM219_FAVORITE_{datetime.now().strftime('%H%M%S')}"
        self.a.open_chat(self.source_group_name)
        sent, evidence = self.a.send_text(token, "im219-source")
        if not sent:
            raise RuntimeError("favorite source message failed")
        _, menu_evidence = self.a.open_menu(token, "im219")
        self.a.click_menu("收藏")
        time.sleep(3)
        evidence += menu_evidence + self.a.snapshot("im219-favorited")
        alice_favorites = self.open_favorites(self.a, self.source_group_name, "im219-alice")
        alice_visible = token in self.a.device.dump_hierarchy()

        bob_as_alice = self.switch_bob_account("smoke_alice", "same-account")
        bob_favorites = self.open_favorites(
            bob_as_alice, self.source_group_name, "im219-bob-same-account"
        )
        bob_as_alice.device(description="刷新").click_exists(timeout=1)
        time.sleep(2)
        synced_to_second = token in bob_as_alice.device.dump_hierarchy()
        removed_evidence = self.remove_favorite(
            bob_as_alice, token, "im219-bob-same-account"
        )
        removed_second = token not in bob_as_alice.device.dump_hierarchy()

        self.a.device.press("back")
        time.sleep(0.8)
        alice_refresh_evidence = self.open_favorites(
            self.a, self.source_group_name, "im219-alice-refresh"
        )
        self.a.device(description="刷新").click_exists(timeout=1)
        time.sleep(3)
        removed_alice = token not in self.a.device.dump_hierarchy()
        self.a.device.press("back")
        time.sleep(1)
        original_retained = self.a.visible_outside_edit(token)
        retained_evidence = self.a.snapshot("im219-original-retained")

        self.b = self.switch_bob_account("smoke_bob", "restored-bob")
        checks = {
            "token": token,
            "alice_favorite_visible": alice_visible,
            "same_account_second_device_synced": synced_to_second,
            "removed_on_second_device": removed_second,
            "removal_synced_back_to_alice": removed_alice,
            "original_message_retained": original_retained,
            "evidence": evidence
            + alice_favorites
            + bob_favorites
            + removed_evidence
            + alice_refresh_evidence
            + retained_evidence,
        }
        self.record(
            "IM-219",
            "PASS"
            if all(
                (
                    alice_visible,
                    synced_to_second,
                    removed_second,
                    removed_alice,
                    original_retained,
                )
            )
            else "FAIL",
            checks,
        )

    def click_header(self, batch: MessageActionBatch, target: str) -> None:
        matches = [
            item
            for item in batch._nodes()
            if item["clickable"]
            and item["top"] < 380
            and target in [line.strip() for line in item["desc"].splitlines()]
        ]
        if not matches:
            raise RuntimeError(f"chat header missing: {target}")
        item = max(
            matches,
            key=lambda row: (row["right"] - row["left"])
            * (row["bottom"] - row["top"]),
        )
        batch.device.click(
            (item["left"] + item["right"]) // 2,
            (item["top"] + item["bottom"]) // 2,
        )
        time.sleep(2)

    def case_clear_for_me(self) -> None:
        token = f"IM210_CLEAR_{datetime.now().strftime('%H%M%S')}"
        send_text(self.api, self.bob, self.private_chat_id, token)
        self.a.device.app_start(self.args.package, stop=True, wait=True)
        self.b.device.app_start(self.args.package, stop=True, wait=True)
        time.sleep(5)
        self.a.open_chat("Smoke Bob")
        if not wait_until(lambda: self.a.visible_outside_edit(token)):
            raise RuntimeError("clear-history source did not reach Alice")
        before = self.a.snapshot("im210-before-clear")
        self.click_header(self.a, "Smoke Bob")
        for _ in range(5):
            if self.a.device(description="清空聊天记录").exists(timeout=0.5):
                break
            self.a.device.swipe(600, 2250, 600, 650, duration=0.6)
            time.sleep(0.7)
        if not self.a.device(description="清空聊天记录").click_exists(timeout=2):
            raise RuntimeError("clear history action missing")
        time.sleep(1)
        dialog = self.a.snapshot("im210-clear-dialog")
        if not self.a.device(description="仅为我清空").click_exists(timeout=2):
            raise RuntimeError("clear-for-me action missing")
        time.sleep(4)
        self.a.device.press("back")
        time.sleep(1)
        alice_cleared = (
            self.a.device(className="android.widget.EditText").exists(timeout=2)
            and not self.a.visible_outside_edit(token)
        )
        after = self.a.snapshot("im210-alice-cleared")
        run_adb(
            self.args.adb,
            self.args.alice,
            "shell",
            "am",
            "force-stop",
            self.args.package,
        )
        self.a.device.app_start(self.args.package, wait=True)
        time.sleep(4)
        self.a.ensure_messages()
        alice_restart_clear = token not in self.a.device.dump_hierarchy()
        restarted = self.a.snapshot("im210-alice-list-after-restart")
        self.b.open_chat("Smoke Alice")
        bob_retained = self.b.visible_outside_edit(token)
        bob_evidence = self.b.snapshot("im210-bob-retained")
        alice_api = not any(
            contains_token(item, token)
            for item in get_messages(self.api, self.alice, self.private_chat_id)
        )
        bob_api = any(
            contains_token(item, token)
            for item in get_messages(self.api, self.bob, self.private_chat_id)
        )
        checks = {
            "token": token,
            "alice_ui_cleared": alice_cleared,
            "alice_restart_did_not_restore": alice_restart_clear,
            "bob_ui_retained": bob_retained,
            "alice_api_filtered": alice_api,
            "bob_api_retained": bob_api,
            "evidence": before + dialog + after + restarted + bob_evidence,
        }
        self.record(
            "IM-210",
            "PASS"
            if all((alice_cleared, alice_restart_clear, bob_retained, alice_api, bob_api))
            else "FAIL",
            checks,
        )

    def run(self) -> dict[str, Any]:
        try:
            self.setup()
            selected = set(
                self.args.only
                or ("IM-199", "IM-210", "IM-215", "IM-216", "IM-219", "IM-220")
            )
            if selected & {"IM-215", "IM-216"}:
                self.case_forward_separate_multi_target()
            if "IM-199" in selected:
                self.case_forward_bundle()
            if "IM-220" in selected:
                self.case_message_detail()
            if "IM-219" in selected:
                self.case_favorite_sync()
            if "IM-210" in selected:
                self.case_clear_for_me()
            expected = selected
            self.result["status"] = (
                "PASS"
                if set(self.result["cases"]) == expected
                and all(
                    case["status"] == "PASS"
                    for case in self.result["cases"].values()
                )
                else "FAIL"
            )
        except Exception as error:  # noqa: BLE001
            self.result["error_type"] = type(error).__name__
            self.result["error"] = str(error)
        finally:
            for chat_id in (self.source_group_id, self.target_group_id):
                if chat_id:
                    try:
                        self.api.request("DELETE", f"/chat/{chat_id}", actor=self.alice)
                    except Exception:
                        pass
            result_path = self.run_dir / "case-result.json"
            self.result["result_path"] = str(result_path)
            result_path.write_text(
                json.dumps(self.result, ensure_ascii=False, indent=2), encoding="utf-8"
            )
            print(json.dumps(self.result, ensure_ascii=False, indent=2), flush=True)
        return self.result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", default=".")
    parser.add_argument("--adb", required=True)
    parser.add_argument("--alice", required=True)
    parser.add_argument("--bob", required=True)
    parser.add_argument("--base", default="http://127.0.0.1:8080/api/v1")
    parser.add_argument("--password", default="Smoke123")
    parser.add_argument("--package", default="com.genericim.app")
    parser.add_argument("--output-dir", required=True)
    parser.add_argument(
        "--only",
        action="append",
        choices=("IM-199", "IM-210", "IM-215", "IM-216", "IM-219", "IM-220"),
    )
    args = parser.parse_args()

    run_dir = Path(args.output_dir).resolve() / datetime.now().strftime(
        "%Y%m%d-%H%M%S"
    )
    run_dir.mkdir(parents=True, exist_ok=True)
    result = StrictMessageUi(args, run_dir).run()
    return 0 if result["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
