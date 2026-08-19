#!/usr/bin/env python3
"""Strict local-Docker UI checks for group profile and permission cases."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import time
import urllib.parse
from datetime import datetime
from pathlib import Path
from typing import Any, Callable

import uiautomator2 as u2


if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")


SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from run_im400_message_actions import MessageActionBatch  # noqa: E402
from run_im400_remaining_api import (  # noqa: E402
    Actor,
    Api,
    ApiError,
    create_chat,
    get_messages,
    list_items,
    response_data,
    send_text,
)
from run_local_group_realtime_real_device import app_fatal_lines, login  # noqa: E402


CASES = (
    "IM-249",
    "IM-262",
    "IM-267",
    "IM-268",
    "IM-269",
    "IM-292",
    "IM-293",
)


def wait_until(
    predicate: Callable[[], bool],
    timeout: int = 20,
    interval: float = 0.8,
) -> bool:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if predicate():
            return True
        time.sleep(interval)
    return False


def contains(value: Any, token: str) -> bool:
    return token in json.dumps(value, ensure_ascii=False, sort_keys=True)


def ui_text_variants(value: str) -> tuple[str, ...]:
    surrogate_sanitized = "".join(".." if ord(char) > 0xFFFF else char for char in value)
    return tuple(dict.fromkeys((value, surrogate_sanitized)))


class StrictGroupUi:
    def __init__(self, args: argparse.Namespace, run_dir: Path) -> None:
        self.args = args
        self.repo = Path(args.repo).resolve()
        self.run_dir = run_dir
        self.alice_dir = run_dir / "alice"
        self.bob_dir = run_dir / "bob"
        self.alice_dir.mkdir(parents=True, exist_ok=True)
        self.bob_dir.mkdir(parents=True, exist_ok=True)
        self.api = Api(args.base.rstrip("/"))
        self.alice = login(self.api, "smoke_alice", args.password, "group-ui-alice")
        self.bob = login(self.api, "smoke_bob", args.password, "group-ui-bob")
        self.a = MessageActionBatch(
            self.repo, self.alice_dir, args.alice, args.package
        )
        self.b = MessageActionBatch(self.repo, self.bob_dir, args.bob, args.package)
        self.profile_group_id = ""
        self.message_group_id = ""
        self.leave_group_id = ""
        self.profile_group_name = ""
        self.profile_group_initial_name = ""
        self.message_group_name = ""
        self.leave_group_name = ""
        self.result: dict[str, Any] = {
            "status": "FAIL",
            "base": args.base,
            "devices": {"alice": args.alice, "bob": args.bob},
            "cases": {},
            "fatal_lines": {},
            "evidence_dir": str(run_dir),
        }

    def record(self, case_id: str, status: str, checks: dict[str, Any]) -> None:
        self.result["cases"][case_id] = {"status": status, "checks": checks}
        self.write_result()
        print(f"[LOCAL-GROUP-UI] {case_id}: {status} {checks}", flush=True)

    def write_result(self) -> None:
        (self.run_dir / "case-result.json").write_text(
            json.dumps(self.result, ensure_ascii=False, indent=2), encoding="utf-8"
        )

    def cleanup_old_groups(self) -> None:
        chats = list_items(
            self.api.request("GET", "/chat/list?page=1&page_size=100", actor=self.alice)
        )
        for chat in chats:
            name = str(chat.get("name") or chat.get("chat_name") or "")
            chat_id = str(chat.get("chat_id") or chat.get("uuid") or "")
            generated_name = name.startswith("LOCAL_GROUP_UI_") or bool(
                re.fullmatch(r"群测😀\d{6}", name)
            )
            if generated_name and chat_id:
                try:
                    self.api.request("DELETE", f"/chat/{chat_id}", actor=self.alice)
                except Exception:
                    pass

    def setup(self) -> None:
        self.cleanup_old_groups()
        stamp = datetime.now().strftime("%H%M%S")
        self.profile_group_name = f"LOCAL_GROUP_UI_P_{stamp}"
        self.profile_group_initial_name = self.profile_group_name
        self.message_group_name = f"LOCAL_GROUP_UI_M_{stamp}"
        self.leave_group_name = f"LOCAL_GROUP_UI_L_{stamp}"
        self.profile_group_id = create_chat(
            self.api, self.alice, 2, [self.bob], self.profile_group_name
        )
        self.message_group_id = create_chat(
            self.api, self.alice, 2, [self.bob], self.message_group_name
        )
        # Leave runs last, so it can reuse the message group without weakening
        # the earlier revoke/receipt checks or consuming a third owned-group slot.
        self.leave_group_id = self.message_group_id
        self.leave_group_name = self.message_group_name
        self.result["groups"] = {
            "profile": {
                "id": self.profile_group_id,
                "name": self.profile_group_name,
            },
            "message": {
                "id": self.message_group_id,
                "name": self.message_group_name,
            },
            "leave": {"id": self.leave_group_id, "name": self.leave_group_name},
        }
        for serial in (self.args.alice, self.args.bob):
            subprocess.run(
                [self.args.adb, "-s", serial, "logcat", "-c"],
                check=False,
                capture_output=True,
            )
        for batch in (self.a, self.b):
            batch.device.app_start(self.args.package, stop=True, wait=True)
        time.sleep(6)
        self.a.ensure_messages()
        self.b.ensure_messages()

    def get_chat(self, actor: Actor, chat_id: str) -> dict[str, Any]:
        data = response_data(
            self.api.request("GET", f"/chat/{chat_id}", actor=actor)
        )
        if not isinstance(data, dict):
            raise RuntimeError(f"invalid chat detail: {data}")
        return data

    def get_user_me(self, actor: Actor) -> dict[str, Any]:
        data = response_data(self.api.request("GET", "/user/me", actor=actor))
        if not isinstance(data, dict):
            raise RuntimeError(f"invalid user profile: {data}")
        return data

    def get_members(self, actor: Actor, chat_id: str) -> list[dict[str, Any]]:
        return list_items(
            self.api.request(
                "GET", f"/chat/{chat_id}/members?page=1&page_size=100", actor=actor
            )
        )

    def member(self, actor: Actor, chat_id: str, user_id: str) -> dict[str, Any]:
        item = next(
            (row for row in self.get_members(actor, chat_id) if row.get("user_id") == user_id),
            None,
        )
        if not isinstance(item, dict):
            raise RuntimeError(f"member missing: {user_id}")
        return item

    def api_rejected(
        self,
        method: str,
        path: str,
        actor: Actor,
        *,
        body: dict[str, Any] | None = None,
        status: int,
    ) -> bool:
        try:
            self.api.request(method, path, actor=actor, body=body)
        except ApiError as error:
            payload_code = error.payload.get("code") if isinstance(error.payload, dict) else None
            try:
                actual_code = int(payload_code if payload_code is not None else error.status)
            except (TypeError, ValueError):
                actual_code = error.status
            return actual_code == status or error.status == status
        return False

    def click_action(self, batch: MessageActionBatch, label: str) -> None:
        for selector in (
            batch.device(description=label),
            batch.device(text=label),
        ):
            if selector.click_exists(timeout=0.8):
                time.sleep(1)
                return
        raise RuntimeError(f"action missing: {label}")

    def click_line(
        self,
        batch: MessageActionBatch,
        label: str,
        *,
        top_min: int = 0,
        top_max_ratio: float = 0.92,
        scroll: bool = False,
    ) -> None:
        width, height = batch.device.window_size()
        variants = ui_text_variants(label)
        for _ in range(10 if scroll else 1):
            matches = [
                item
                for item in batch._nodes()
                if item["clickable"]
                and item["top"] >= top_min
                and item["top"] < int(height * top_max_ratio)
                and any(
                    variant
                    in [
                        line.strip()
                        for line in item["desc"].splitlines()
                        if line.strip()
                    ]
                    for variant in variants
                )
            ]
            if matches:
                item = min(
                    matches,
                    key=lambda row: max(1, row["right"] - row["left"])
                    * max(1, row["bottom"] - row["top"]),
                )
                batch.device.click(
                    (item["left"] + item["right"]) // 2,
                    (item["top"] + item["bottom"]) // 2,
                )
                time.sleep(1.5)
                return
            if scroll:
                batch.device.swipe(
                    width // 2,
                    int(height * 0.82),
                    width // 2,
                    int(height * 0.42),
                    duration=0.5,
                )
                time.sleep(0.7)
        raise RuntimeError(f"semantic line missing: {label}")

    def open_profile(self, batch: MessageActionBatch, group_name: str) -> list[str]:
        candidates = list(ui_text_variants(group_name))
        if (
            group_name == self.profile_group_name
            and self.profile_group_initial_name
            and self.profile_group_initial_name != group_name
        ):
            candidates.extend(ui_text_variants(self.profile_group_initial_name))
        evidence: list[str] = []
        opened_name = ""
        errors: list[str] = []
        for attempt in range(2):
            for candidate in candidates:
                try:
                    evidence = batch.open_chat(candidate)
                    opened_name = candidate
                    break
                except Exception as error:  # noqa: BLE001
                    errors.append(str(error))
                    batch.device = u2.connect(batch.serial)
            if opened_name:
                break
            if attempt == 0:
                batch.device.app_start(self.args.package, stop=True, wait=True)
                time.sleep(4)
        if not opened_name:
            raise RuntimeError("; ".join(errors))
        self.dismiss_heads_up(batch)
        for header_name in dict.fromkeys(
            (*ui_text_variants(group_name), opened_name)
        ):
            try:
                self.click_line(batch, header_name, top_max_ratio=0.18)
                break
            except RuntimeError:
                continue
        else:
            raise RuntimeError(f"group chat header missing: {group_name}")
        if not wait_until(
            lambda: any(
                marker in batch.device.dump_hierarchy()
                for marker in ("群成员", "群简介", "暂无简介")
            ),
            timeout=8,
        ):
            raise RuntimeError(f"group profile did not open: {group_name}")
        return evidence + batch.snapshot("group-profile-opened")

    def open_chat(self, batch: MessageActionBatch, group_name: str) -> list[str]:
        errors: list[str] = []
        for attempt in range(2):
            try:
                evidence = batch.open_chat(group_name)
                self.dismiss_heads_up(batch)
                return evidence
            except Exception as error:  # noqa: BLE001
                errors.append(str(error))
                batch.device = u2.connect(batch.serial)
                if attempt == 0:
                    batch.device.app_start(self.args.package, stop=True, wait=True)
                    time.sleep(4)
        raise RuntimeError("; ".join(errors))

    def click_top_right(self, batch: MessageActionBatch) -> None:
        for label in ("更多", "菜单"):
            if batch.device(description=label).click_exists(timeout=0.5):
                time.sleep(1)
                return
        width, height = batch.device.window_size()
        candidates = [
            item
            for item in batch._nodes()
            if item["clickable"]
            and item["left"] > int(width * 0.72)
            and 100 < item["top"] < int(height * 0.18)
        ]
        if not candidates:
            raise RuntimeError("top-right action missing")
        item = max(candidates, key=lambda row: row["left"])
        batch.device.click(
            (item["left"] + item["right"]) // 2,
            (item["top"] + item["bottom"]) // 2,
        )
        time.sleep(1)

    def dismiss_heads_up(self, batch: MessageActionBatch) -> None:
        width, height = batch.device.window_size()
        covered = any(
            item["package"] == "com.android.systemui"
            and item["top"] < int(height * 0.30)
            and item["bottom"] > int(height * 0.12)
            for item in batch._nodes()
        )
        if not covered:
            return
        batch.device.swipe(
            width // 2,
            int(height * 0.22),
            width // 2,
            int(height * 0.04),
            duration=0.35,
        )
        time.sleep(1)

    def open_edit(self, group_name: str) -> list[str]:
        evidence = self.open_profile(self.a, group_name)
        self.click_top_right(self.a)
        evidence += self.a.snapshot("group-more-menu")
        self.click_action(self.a, "编辑群组")
        if not wait_until(
            lambda: self.a.device(className="android.widget.EditText").count >= 2,
            timeout=8,
        ):
            raise RuntimeError("group profile edit fields missing")
        return evidence + self.a.snapshot("group-edit-opened")

    def set_field(self, batch: MessageActionBatch, index: int, value: str) -> str:
        field = batch.device(className="android.widget.EditText", instance=index)
        if not field.exists(timeout=2):
            raise RuntimeError(f"edit field missing: {index}")
        field.click()
        batch.device.set_input_ime(True)
        batch.device.send_keys(value, clear=True)
        time.sleep(0.6)
        return field.get_text()

    def wait_api_chat(
        self, chat_id: str, predicate: Callable[[dict[str, Any]], bool], timeout: int = 15
    ) -> bool:
        return wait_until(lambda: predicate(self.get_chat(self.alice, chat_id)), timeout)

    def chat_row_exists(self, batch: MessageActionBatch, group_name: str) -> bool:
        try:
            batch.ensure_messages()
        except Exception:
            return False
        variants = ui_text_variants(group_name)
        return any(
            any(
                variant
                in [
                    line.strip()
                    for line in item["desc"].splitlines()[:3]
                    if line.strip()
                ]
                for variant in variants
            )
            for item in batch._nodes()
        )

    def ui_contains(self, batch: MessageActionBatch, token: str) -> bool:
        variants = ui_text_variants(token)
        return any(
            any(variant in f"{item['desc']} {item['text']}" for variant in variants)
            for item in batch._nodes()
        )

    def case_profile_boundaries(self, selected: set[str]) -> None:
        evidence = self.open_edit(self.profile_group_name)
        original = self.profile_group_name

        self.set_field(self.a, 0, "   ")
        self.click_action(self.a, "完成")
        blank_rejected = wait_until(
            lambda: "群组名称不能为空" in self.a.device.dump_hierarchy(), timeout=5
        )
        evidence += self.a.snapshot("im262-blank-rejected")

        overlong_input = "N" * 33
        entered_overlong = self.set_field(self.a, 0, overlong_input)
        ui_length_limited = len(entered_overlong) <= 32
        evidence += self.a.snapshot("im262-ui-length-limit")

        blocked_name = f"{self.args.blocked_word}_{datetime.now().strftime('%H%M%S')}"
        self.set_field(self.a, 0, blocked_name)
        self.click_action(self.a, "完成")
        blocked_rejected = wait_until(
            lambda: "群名称包含不允许的内容" in self.a.device.dump_hierarchy(),
            timeout=8,
        )
        blocked_unchanged = self.get_chat(self.alice, self.profile_group_id).get(
            "name"
        ) == original
        evidence += self.a.snapshot("im262-sensitive-rejected")

        legal_name = f"群测😀{datetime.now().strftime('%H%M%S')}"
        legal_description = f"群简介😀{datetime.now().strftime('%H%M%S')}"
        self.set_field(self.a, 0, legal_name)
        self.set_field(self.a, 1, legal_description)
        self.click_action(self.a, "完成")
        legal_persisted = self.wait_api_chat(
            self.profile_group_id,
            lambda chat: chat.get("name") == legal_name
            and chat.get("description") == legal_description,
        )
        if not legal_persisted:
            raise RuntimeError("legal group profile edit did not persist")
        evidence += self.a.snapshot("im262-im267-legal-saved")
        self.profile_group_name = legal_name

        bob_evidence = self.open_profile(self.b, legal_name)
        cross_device_description = self.ui_contains(self.b, legal_description)
        cross_device_name_visible = self.ui_contains(self.b, legal_name)
        bob_evidence += self.b.snapshot("im267-description-cross-device")

        api_name_overlong_rejected = self.api_rejected(
            "PUT",
            f"/chat/{self.profile_group_id}",
            self.alice,
            body={"name": "X" * 33},
            status=400,
        )
        api_description_spaces_rejected = self.api_rejected(
            "PUT",
            f"/chat/{self.profile_group_id}",
            self.alice,
            body={"description": "   "},
            status=400,
        )
        api_description_overlong_rejected = self.api_rejected(
            "PUT",
            f"/chat/{self.profile_group_id}",
            self.alice,
            body={"description": "D" * 1001},
            status=400,
        )

        clear_evidence = self.open_edit(legal_name)
        self.set_field(self.a, 1, "")
        self.click_action(self.a, "完成")
        description_cleared = self.wait_api_chat(
            self.profile_group_id, lambda chat: chat.get("description") in ("", None)
        )
        clear_evidence += self.a.snapshot("im267-description-cleared")
        clear_visible_bob = wait_until(
            lambda: "暂无简介" in self.b.device.dump_hierarchy(), timeout=15
        )
        cleared_bob_evidence: list[str] = []
        cleared_bob_evidence += self.b.snapshot("im267-clear-cross-device")

        all_evidence = evidence + bob_evidence + clear_evidence + cleared_bob_evidence
        if "IM-262" in selected:
            checks_262 = {
                "blank_rejected_in_ui": blank_rejected,
                "ui_33_character_input_limited": ui_length_limited,
                "ui_visible_length": len(entered_overlong),
                "api_33_character_name_rejected": api_name_overlong_rejected,
                "blocked_word_rejected_in_ui": blocked_rejected,
                "blocked_attempt_did_not_mutate_name": blocked_unchanged,
                "emoji_name_persisted": legal_persisted,
                "bob_profile_shows_new_name": cross_device_name_visible,
                "legal_name": legal_name,
                "evidence": all_evidence,
            }
            self.record(
                "IM-262",
                "PASS"
                if all(
                    value
                    for key, value in checks_262.items()
                    if key
                    not in (
                        "ui_visible_length",
                        "legal_name",
                        "bob_profile_shows_new_name",
                        "evidence",
                    )
                )
                else "FAIL",
                checks_262,
            )
        if "IM-267" in selected:
            checks_267 = {
                "description_persisted": legal_persisted,
                "description_visible_on_bob": cross_device_description,
                "api_whitespace_only_rejected": api_description_spaces_rejected,
                "api_1001_characters_rejected": api_description_overlong_rejected,
                "description_cleared": description_cleared,
                "clear_visible_on_bob": clear_visible_bob,
                "evidence": all_evidence,
            }
            self.record(
                "IM-267",
                "PASS" if all(value for key, value in checks_267.items() if key != "evidence") else "FAIL",
                checks_267,
            )

    def edit_member_nickname(
        self,
        batch: MessageActionBatch,
        group_name: str,
        member_label: str,
        action_label: str,
        nickname: str,
        evidence_prefix: str,
    ) -> list[str]:
        evidence = self.open_profile(batch, group_name)
        self.click_line(batch, member_label, top_min=350, scroll=True)
        evidence += batch.snapshot(f"{evidence_prefix}-member-actions")
        self.click_action(batch, action_label)
        if not wait_until(
            lambda: "修改群昵称" in batch.device.dump_hierarchy()
            and batch.device(className="android.widget.EditText").count >= 1,
            timeout=5,
        ):
            raise RuntimeError("nickname dialog missing")
        self.set_field(batch, 0, nickname)
        self.click_action(batch, "确定")
        wait_until(lambda: "群昵称已更新" in batch.device.dump_hierarchy(), timeout=6)
        return evidence + batch.snapshot(f"{evidence_prefix}-nickname-updated")

    def case_nicknames(self, selected: set[str]) -> None:
        stamp = datetime.now().strftime("%H%M%S")
        global_nickname_before = str(self.get_user_me(self.bob).get("nickname") or "")
        self_nickname = f"Bob群😀{stamp}"
        evidence_self = self.edit_member_nickname(
            self.b,
            self.profile_group_name,
            "Smoke Bob",
            "修改我的群昵称",
            self_nickname,
            "im268-self",
        )
        self_nickname_persisted = wait_until(
            lambda: self.member(
                self.bob, self.profile_group_id, self.bob.user_id
            ).get("nickname_in_chat")
            == self_nickname,
            timeout=10,
        )
        global_nickname_after = str(self.get_user_me(self.bob).get("nickname") or "")
        global_nickname_unchanged = (
            bool(global_nickname_before)
            and global_nickname_after == global_nickname_before
        )

        owner_nickname = f"Bob管{stamp}"
        evidence_owner = self.edit_member_nickname(
            self.a,
            self.profile_group_name,
            self_nickname,
            "修改群昵称",
            owner_nickname,
            "im269-owner",
        )
        owner_nickname_persisted = wait_until(
            lambda: self.member(
                self.alice, self.profile_group_id, self.bob.user_id
            ).get("nickname_in_chat")
            == owner_nickname,
            timeout=10,
        )

        evidence_denied = self.open_profile(self.b, self.profile_group_name)
        self.click_line(self.b, "Smoke Alice", top_min=350, scroll=True)
        time.sleep(1)
        ordinary_ui_cannot_edit_other = "修改群昵称" not in self.b.device.dump_hierarchy()
        evidence_denied += self.b.snapshot("im269-ordinary-other-profile")
        self.b.device.press("back")
        api_denied = self.api_rejected(
            "PUT",
            f"/chat/{self.profile_group_id}/members/{self.alice.user_id}/nickname",
            self.bob,
            body={"nickname": "DENIED"},
            status=403,
        )

        if "IM-268" in selected:
            checks_268 = {
                "self_nickname_persisted": self_nickname_persisted,
                "global_nickname_unchanged": global_nickname_unchanged,
                "global_nickname_before": global_nickname_before,
                "global_nickname_after": global_nickname_after,
                "nickname": self_nickname,
                "evidence": evidence_self,
            }
            self.record(
                "IM-268",
                "PASS"
                if self_nickname_persisted and global_nickname_unchanged
                else "FAIL",
                checks_268,
            )
        if "IM-269" in selected:
            checks_269 = {
                "owner_nickname_persisted": owner_nickname_persisted,
                "ordinary_member_has_no_edit_action_for_owner": ordinary_ui_cannot_edit_other,
                "ordinary_member_api_denied": api_denied,
                "nickname": owner_nickname,
                "evidence": evidence_owner + evidence_denied,
            }
            self.record(
                "IM-269",
                "PASS"
                if owner_nickname_persisted
                and ordinary_ui_cannot_edit_other
                and api_denied
                else "FAIL",
                checks_269,
            )

    def case_admin_revoke(self) -> None:
        stamp = datetime.now().strftime("%H%M%S")
        member_token = f"IM292_MEMBER_{stamp}"
        member_message = send_text(
            self.api, self.bob, self.message_group_id, member_token
        )
        evidence = self.open_chat(self.a, self.message_group_name)
        wait_until(lambda: self.a.visible_outside_edit(member_token), timeout=12)
        evidence += self.open_chat(self.b, self.message_group_name)
        wait_until(lambda: self.b.visible_outside_edit(member_token), timeout=12)
        menu, menu_evidence = self.a.open_menu(member_token, "im292-owner-revoke")
        evidence += menu_evidence
        owner_has_revoke = "撤回" in menu
        self.a.click_menu("撤回")
        self.a.confirm_if_present("撤回")
        admin_marker_alice = wait_until(
            lambda: "管理员撤回了一条消息" in self.a.device.dump_hierarchy(),
            timeout=12,
        )
        admin_marker_bob = wait_until(
            lambda: "管理员撤回了一条消息" in self.b.device.dump_hierarchy(),
            timeout=12,
        )
        evidence += self.a.snapshot("im292-owner-revoked-alice")
        evidence += self.b.snapshot("im292-owner-revoked-bob")
        revoked = next(
            (
                item
                for item in get_messages(
                    self.api, self.bob, self.message_group_id
                )
                if item.get("msg_id") == member_message.get("msg_id")
            ),
            {},
        )
        authoritative_revoke = (
            revoked.get("is_revoked") is True
            and revoked.get("revoked_by") == self.alice.user_id
        )

        owner_token = f"IM292_OWNER_{stamp}"
        owner_message = send_text(
            self.api, self.alice, self.message_group_id, owner_token
        )
        wait_until(lambda: self.b.visible_outside_edit(owner_token), timeout=12)
        bob_menu, bob_menu_evidence = self.b.open_menu(
            owner_token, "im292-ordinary-menu"
        )
        evidence += bob_menu_evidence
        ordinary_has_no_revoke = "撤回" not in bob_menu
        self.b.device.press("back")
        api_denied = self.api_rejected(
            "POST",
            "/message/revoke",
            self.bob,
            body={
                "chat_id": self.message_group_id,
                "msg_id": owner_message.get("msg_id"),
            },
            status=400,
        )
        checks = {
            "owner_ui_has_revoke": owner_has_revoke,
            "admin_marker_alice": admin_marker_alice,
            "admin_marker_bob": admin_marker_bob,
            "authoritative_revoked_by_owner": authoritative_revoke,
            "ordinary_member_ui_has_no_peer_revoke": ordinary_has_no_revoke,
            "ordinary_member_api_denied": api_denied,
            "evidence": evidence,
        }
        self.record(
            "IM-292",
            "PASS" if all(value for key, value in checks.items() if key != "evidence") else "FAIL",
            checks,
        )

    def message_detail(self, actor: Actor, chat_id: str, msg_id: str) -> dict[str, Any]:
        query = urllib.parse.urlencode({"chat_id": chat_id, "msg_id": msg_id})
        data = response_data(
            self.api.request("GET", f"/message/detail?{query}", actor=actor)
        )
        return data if isinstance(data, dict) else {}

    def case_receipts(self) -> None:
        stamp = datetime.now().strftime("%H%M%S")
        token = f"IM293_RECEIPT_{stamp}"
        message = send_text(self.api, self.alice, self.message_group_id, token)
        self.open_chat(self.b, self.message_group_name)
        bob_received = wait_until(lambda: self.b.visible_outside_edit(token), timeout=12)
        owner_detail_ready = wait_until(
            lambda: int(
                self.message_detail(
                    self.alice, self.message_group_id, str(message.get("msg_id"))
                ).get("receipts", {}).get("read_count", 0)
            )
            >= 1,
            timeout=15,
        )

        evidence = self.open_chat(self.a, self.message_group_name)
        wait_until(lambda: self.a.visible_outside_edit(token), timeout=8)
        _, owner_menu = self.a.open_menu(token, "im293-owner-detail")
        evidence += owner_menu
        self.a.click_menu("消息详情")
        owner_xml_ready = wait_until(
            lambda: "消息详情" in self.a.device.dump_hierarchy()
            and "成员状态" in self.a.device.dump_hierarchy(),
            timeout=10,
        )
        owner_xml = self.a.device.dump_hierarchy()
        owner_can_view_members = owner_xml_ready and "Smoke Bob" in owner_xml
        evidence += self.a.snapshot("im293-owner-member-receipts")
        self.a.device.press("back")

        _, ordinary_menu = self.b.open_menu(token, "im293-ordinary-detail")
        evidence += ordinary_menu
        self.b.click_menu("消息详情")
        ordinary_xml_ready = wait_until(
            lambda: "消息详情" in self.b.device.dump_hierarchy()
            and "为保护成员隐私，你只能查看汇总数据。"
            in self.b.device.dump_hierarchy(),
            timeout=10,
        )
        ordinary_xml = self.b.device.dump_hierarchy()
        ordinary_summary_only = ordinary_xml_ready and "成员状态" not in ordinary_xml
        evidence += self.b.snapshot("im293-ordinary-summary-only")

        owner_detail = self.message_detail(
            self.alice, self.message_group_id, str(message.get("msg_id"))
        )
        ordinary_detail = self.message_detail(
            self.bob, self.message_group_id, str(message.get("msg_id"))
        )
        owner_receipts = owner_detail.get("receipts", {})
        ordinary_receipts = ordinary_detail.get("receipts", {})
        api_permissions = (
            owner_receipts.get("can_view_members") is True
            and ordinary_receipts.get("can_view_members") is False
            and ordinary_receipts.get("members") == []
        )
        checks = {
            "bob_received_and_read": bob_received and owner_detail_ready,
            "owner_ui_can_view_member_status": owner_can_view_members,
            "ordinary_ui_summary_only": ordinary_summary_only,
            "api_receipt_permissions_match_ui": api_permissions,
            "owner_read_count": owner_receipts.get("read_count"),
            "evidence": evidence,
        }
        self.record(
            "IM-293",
            "PASS"
            if bob_received
            and owner_detail_ready
            and owner_can_view_members
            and ordinary_summary_only
            and api_permissions
            else "FAIL",
            checks,
        )

    def case_leave(self) -> None:
        stamp = datetime.now().strftime("%H%M%S")
        marker = f"IM249_BEFORE_{stamp}"
        send_text(self.api, self.alice, self.leave_group_id, marker)
        members_before = int(
            self.get_chat(self.alice, self.leave_group_id).get("member_count", 0)
        )
        audit_before = [
            item
            for item in get_messages(self.api, self.alice, self.leave_group_id)
            if int(item.get("type", 0)) == 99
        ]
        evidence = self.open_profile(self.b, self.leave_group_name)
        self.click_top_right(self.b)
        evidence += self.b.snapshot("im249-member-more-menu")
        self.click_action(self.b, "退出群组")
        confirmation_visible = wait_until(
            lambda: "退出后将不再接收此群组的消息"
            in self.b.device.dump_hierarchy(),
            timeout=5,
        )
        evidence += self.b.snapshot("im249-leave-confirmation")
        self.click_action(self.b, "退出群组")
        returned_to_main = wait_until(
            lambda: "联系人" in self.b.device.dump_hierarchy()
            and "设置" in self.b.device.dump_hierarchy(),
            timeout=12,
        )
        group_removed_from_bob = wait_until(
            lambda: not self.chat_row_exists(self.b, self.leave_group_name),
            timeout=10,
        )
        evidence += self.b.snapshot("im249-bob-chat-removed")
        member_count_decremented = wait_until(
            lambda: int(
                self.get_chat(self.alice, self.leave_group_id).get(
                    "member_count", 0
                )
            )
            == members_before - 1,
            timeout=12,
        )
        send_denied = self.api_rejected(
            "POST",
            "/message/send",
            self.bob,
            body={
                "chat_id": self.leave_group_id,
                "type": 1,
                "content": {"text": f"AFTER_LEAVE_{stamp}"},
                "msg_id": f"after-leave-{stamp}",
            },
            status=403,
        )
        search_query = urllib.parse.urlencode({"keyword": marker})
        search_denied = self.api_rejected(
            "GET",
            f"/chat/{self.leave_group_id}/search?{search_query}",
            self.bob,
            status=403,
        )
        audit_after = [
            item
            for item in get_messages(self.api, self.alice, self.leave_group_id)
            if int(item.get("type", 0)) == 99
        ]
        audit_appended_once = len(audit_after) == len(audit_before) + 1
        evidence += self.open_chat(self.a, self.leave_group_name)
        audit_visible_alice = wait_until(
            lambda: "Smoke Bob 退出了群组" in self.a.device.dump_hierarchy(),
            timeout=10,
        )
        evidence += self.a.snapshot("im249-alice-audit-visible")
        checks = {
            "leave_confirmation_visible": confirmation_visible,
            "returned_to_main": returned_to_main,
            "group_removed_from_bob": group_removed_from_bob,
            "member_count_decremented": member_count_decremented,
            "send_after_leave_denied": send_denied,
            "search_after_leave_denied": search_denied,
            "audit_appended_exactly_once": audit_appended_once,
            "audit_visible_on_alice": audit_visible_alice,
            "evidence": evidence,
        }
        self.record(
            "IM-249",
            "PASS" if all(value for key, value in checks.items() if key != "evidence") else "FAIL",
            checks,
        )

    def run(self) -> dict[str, Any]:
        selected = set(self.args.only or CASES)
        try:
            self.setup()
            if selected & {"IM-262", "IM-267"}:
                self.case_profile_boundaries(selected)
            if selected & {"IM-268", "IM-269"}:
                self.case_nicknames(selected)
            if "IM-292" in selected:
                self.case_admin_revoke()
            if "IM-293" in selected:
                self.case_receipts()
            if "IM-249" in selected:
                self.case_leave()

            fatal_alice = app_fatal_lines(
                self.args.adb, self.args.alice, self.args.package
            )
            fatal_bob = app_fatal_lines(
                self.args.adb, self.args.bob, self.args.package
            )
            self.result["fatal_lines"] = {
                self.args.alice: fatal_alice,
                self.args.bob: fatal_bob,
            }
            self.result["fatal_anr_flutter_error_zero"] = (
                not fatal_alice and not fatal_bob
            )
            self.result["status"] = (
                "PASS"
                if set(self.result["cases"]) == selected
                and all(
                    item["status"] == "PASS"
                    for item in self.result["cases"].values()
                )
                and self.result["fatal_anr_flutter_error_zero"]
                else "FAIL"
            )
        except Exception as error:  # noqa: BLE001
            self.result["error_type"] = type(error).__name__
            self.result["error"] = str(error)
        finally:
            for chat_id in (
                self.profile_group_id,
                self.message_group_id,
                self.leave_group_id,
            ):
                if not chat_id:
                    continue
                try:
                    self.api.request("DELETE", f"/chat/{chat_id}", actor=self.alice)
                except Exception:
                    pass
            self.result["result_path"] = str(self.run_dir / "case-result.json")
            self.write_result()
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
    parser.add_argument("--package", default="com.genericim.ma100")
    parser.add_argument("--blocked-word", required=True)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--only", action="append", choices=CASES)
    args = parser.parse_args()

    run_dir = Path(args.output_dir).resolve() / datetime.now().strftime(
        "%Y%m%d-%H%M%S"
    )
    run_dir.mkdir(parents=True, exist_ok=True)
    result = StrictGroupUi(args, run_dir).run()
    return 0 if result["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
