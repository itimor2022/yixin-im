#!/usr/bin/env python3
"""Strict local-Docker call lifecycle checks on two physical Android devices."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import threading
import time
from datetime import datetime
from pathlib import Path
from typing import Any, Callable

import uiautomator2 as u2


SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from prepare_dual_device_apk import run_adb  # noqa: E402
from run_im400_message_actions import MessageActionBatch  # noqa: E402
from run_im400_remaining_api import (  # noqa: E402
    Actor,
    Api,
    create_chat,
    response_data,
)
from run_local_group_realtime_real_device import app_fatal_lines, login  # noqa: E402


if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")


CASES = (
    "IM-305",
    "IM-308",
    "IM-313",
    "IM-314",
    "IM-315",
    "IM-318",
    "IM-323",
    "IM-324",
    "IM-337",
)


def wait_until(
    predicate: Callable[[], bool], timeout: int = 20, interval: float = 0.8
) -> bool:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            if predicate():
                return True
        except Exception:
            pass
        time.sleep(interval)
    return False


class StrictCallUi:
    def __init__(self, args: argparse.Namespace, run_dir: Path) -> None:
        self.args = args
        self.repo = Path(args.repo).resolve()
        self.run_dir = run_dir
        self.alice_dir = run_dir / "alice"
        self.bob_dir = run_dir / "bob"
        self.alice_dir.mkdir(parents=True, exist_ok=True)
        self.bob_dir.mkdir(parents=True, exist_ok=True)
        self.api = Api(args.base.rstrip("/"))
        self.alice = login(self.api, "smoke_alice", args.password, "call-ui-alice")
        self.bob = login(self.api, "smoke_bob", args.password, "call-ui-bob")
        self.chat_id = create_chat(self.api, self.alice, 1, [self.bob])
        self.a = MessageActionBatch(
            self.repo, self.alice_dir, args.alice, args.package
        )
        self.b = MessageActionBatch(self.repo, self.bob_dir, args.bob, args.package)
        self.result: dict[str, Any] = {
            "status": "FAIL",
            "base": args.base,
            "devices": {"alice": args.alice, "bob": args.bob},
            "chat_id": self.chat_id,
            "cases": {},
            "fatal_lines": {},
            "evidence_dir": str(run_dir),
        }

    def write_result(self) -> None:
        (self.run_dir / "case-result.json").write_text(
            json.dumps(self.result, ensure_ascii=False, indent=2), encoding="utf-8"
        )

    def record(self, case_id: str, status: str, checks: dict[str, Any]) -> None:
        self.result["cases"][case_id] = {"status": status, "checks": checks}
        self.write_result()
        print(f"[LOCAL-CALL-UI] {case_id}: {status} {checks}", flush=True)

    def setup(self) -> None:
        self.set_wifi(self.args.alice, True)
        self.set_wifi(self.args.bob, True)
        self.end_active_call()
        for serial in (self.args.alice, self.args.bob):
            for permission in (
                "android.permission.RECORD_AUDIO",
                "android.permission.CAMERA",
            ):
                try:
                    run_adb(
                        self.args.adb,
                        serial,
                        "shell",
                        "pm",
                        "grant",
                        self.args.package,
                        permission,
                    )
                except Exception:
                    pass
            subprocess.run(
                [self.args.adb, "-s", serial, "logcat", "-c"],
                check=False,
                capture_output=True,
            )
        for batch in (self.a, self.b):
            batch.device.app_start(self.args.package, stop=True, wait=True)
        time.sleep(5)
        self.a.ensure_messages()
        self.b.ensure_messages()

    def reconnect(self, batch: MessageActionBatch) -> None:
        batch.device = u2.connect(batch.serial)

    def click_exact(self, batch: MessageActionBatch, label: str) -> None:
        for selector in (batch.device(description=label), batch.device(text=label)):
            if selector.click_exists(timeout=1):
                time.sleep(0.8)
                return
        raise RuntimeError(f"action missing: {label}")

    def click_button_exact(self, batch: MessageActionBatch, label: str) -> None:
        matches = [
            item
            for item in batch._nodes()
            if item["clickable"]
            and (item["desc"] == label or item["text"] == label)
        ]
        buttons = [
            item for item in matches if item["class"] == "android.widget.Button"
        ]
        candidates = buttons or matches
        if not candidates:
            raise RuntimeError(f"button action missing: {label}")
        item = max(candidates, key=lambda row: (row["top"], row["bottom"]))
        batch.device.click(
            (item["left"] + item["right"]) // 2,
            (item["top"] + item["bottom"]) // 2,
        )
        time.sleep(0.8)

    def dismiss_permissions(self, batch: MessageActionBatch, timeout: int = 12) -> None:
        labels = (
            "允许",
            "始终允许",
            "仅在使用中允许",
            "仅在使用该应用时允许",
            "使用应用时允许",
            "确定",
        )
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            clicked = False
            for label in labels:
                if batch.device(text=label).click_exists(timeout=0.2):
                    clicked = True
                    time.sleep(0.8)
                    break
            if not clicked:
                return

    def dismiss_heads_up(self, batch: MessageActionBatch) -> None:
        width, height = batch.device.window_size()
        covered = any(
            item["package"] == "com.android.systemui"
            and item["bottom"] > int(height * 0.12)
            and item["top"] < int(height * 0.30)
            for item in batch._nodes()
        )
        if covered:
            batch.device.swipe(
                width // 2,
                int(height * 0.22),
                width // 2,
                int(height * 0.04),
                duration=0.35,
            )
            time.sleep(1)

    def open_chat(self, batch: MessageActionBatch, peer_name: str) -> list[str]:
        errors: list[str] = []
        for attempt in range(2):
            try:
                evidence = batch.open_chat(peer_name)
                self.dismiss_heads_up(batch)
                return evidence
            except Exception as error:  # noqa: BLE001
                errors.append(str(error))
                self.reconnect(batch)
                if attempt == 0:
                    batch.device.app_start(self.args.package, stop=True, wait=True)
                    time.sleep(4)
        raise RuntimeError("; ".join(errors))

    def click_header(self, batch: MessageActionBatch, peer_name: str) -> None:
        height = batch.device.window_size()[1]
        matches = [
            item
            for item in batch._nodes()
            if item["clickable"]
            and item["top"] < int(height * 0.18)
            and peer_name
            in [line.strip() for line in item["desc"].splitlines() if line.strip()]
        ]
        if not matches:
            raise RuntimeError(f"chat header missing: {peer_name}")
        item = max(
            matches,
            key=lambda row: max(1, row["right"] - row["left"])
            * max(1, row["bottom"] - row["top"]),
        )
        batch.device.click(
            (item["left"] + item["right"]) // 2,
            (item["top"] + item["bottom"]) // 2,
        )
        time.sleep(1.5)

    def open_peer_profile(
        self, batch: MessageActionBatch, peer_name: str
    ) -> list[str]:
        evidence = self.open_chat(batch, peer_name)
        self.click_header(batch, peer_name)
        if not wait_until(
            lambda: "个人简介" in batch.device.dump_hierarchy()
            and "通话" in batch.device.dump_hierarchy()
            and "视频" in batch.device.dump_hierarchy(),
            timeout=10,
        ):
            raise RuntimeError(f"peer profile did not open: {peer_name}")
        return evidence + batch.snapshot("peer-profile-opened")

    def timer_seconds(self, batch: MessageActionBatch) -> int:
        values: list[int] = []
        for item in batch._nodes():
            if item["package"] != self.args.package:
                continue
            for match in re.finditer(r"(?<!\d)(\d{2}):(\d{2})(?!\d)", f"{item['desc']} {item['text']}"):
                values.append(int(match.group(1)) * 60 + int(match.group(2)))
        return max(values, default=-1)

    def call_surface(self, batch: MessageActionBatch, connected: bool = False) -> bool:
        xml = batch.device.dump_hierarchy()
        if connected:
            return "挂断" in xml and self.timer_seconds(batch) >= 0
        return any(marker in xml for marker in ("取消", "接听", "挂断", "呼叫中"))

    def active_call(self, actor: Actor | None = None) -> dict[str, Any]:
        data = response_data(
            self.api.request("GET", "/call/active", actor=actor or self.alice)
        )
        return data if isinstance(data, dict) else {}

    def end_active_call(self) -> None:
        for actor in (self.alice, self.bob):
            try:
                active = self.active_call(actor)
                call_id = int(active.get("call_id", 0))
                if active.get("active") is True and call_id > 0:
                    self.api.request(
                        "POST",
                        "/call/end",
                        actor=actor,
                        body={"call_id": call_id, "reason": "qa_cleanup"},
                    )
            except Exception:
                pass
        time.sleep(1)

    def start_call(self, kind: str) -> tuple[dict[str, Any], list[str]]:
        self.end_active_call()
        for batch in (self.a, self.b):
            batch.device.app_start(self.args.package, stop=True, wait=True)
        time.sleep(4)
        self.b.ensure_messages()
        evidence = self.open_peer_profile(self.a, "Smoke Bob")
        self.click_exact(self.a, "视频" if kind == "video" else "通话")
        self.dismiss_permissions(self.a)
        outgoing_ready = wait_until(lambda: self.call_surface(self.a), timeout=15)
        if not outgoing_ready and "个人简介" in self.a.device.dump_hierarchy():
            self.click_exact(self.a, "视频" if kind == "video" else "通话")
            self.dismiss_permissions(self.a)
            outgoing_ready = wait_until(
                lambda: self.call_surface(self.a), timeout=15
            )
        if not outgoing_ready:
            raise RuntimeError(f"Alice {kind} outgoing surface missing")
        evidence += self.a.snapshot(f"{kind}-alice-outgoing")

        if not wait_until(
            lambda: self.b.device(description="接听").exists(timeout=0.2)
            or self.b.device(text="接听").exists(timeout=0.2),
            timeout=18,
        ):
            raise RuntimeError(f"Bob {kind} incoming surface missing")
        evidence += self.b.snapshot(f"{kind}-bob-incoming")
        self.click_exact(self.b, "接听")
        self.dismiss_permissions(self.b, timeout=15)
        if not wait_until(
            lambda: self.call_surface(self.a, connected=True)
            and self.call_surface(self.b, connected=True),
            timeout=25,
        ):
            raise RuntimeError(f"{kind} call did not connect on both devices")
        evidence += self.a.snapshot(f"{kind}-alice-connected")
        evidence += self.b.snapshot(f"{kind}-bob-connected")
        active = self.active_call()
        if active.get("active") is not True:
            raise RuntimeError(f"connected {kind} call missing from API: {active}")
        return active, evidence

    def hang_up(self) -> None:
        for batch in (self.a, self.b):
            try:
                if batch.device(description="挂断").click_exists(timeout=0.5):
                    break
                if batch.device(text="挂断").click_exists(timeout=0.5):
                    break
            except Exception:
                self.reconnect(batch)
        wait_until(lambda: self.active_call().get("active") is not True, timeout=12)
        time.sleep(2)

    def set_wifi(self, serial: str, enabled: bool) -> None:
        run_adb(
            self.args.adb,
            serial,
            "shell",
            "svc",
            "wifi",
            "enable" if enabled else "disable",
        )
        time.sleep(2)

    def case_lock_and_background(self, selected: set[str]) -> None:
        active, evidence = self.start_call("voice")
        time.sleep(4)
        before_lock = self.timer_seconds(self.b)
        run_adb(self.args.adb, self.args.bob, "shell", "input", "keyevent", "26")
        time.sleep(8)
        run_adb(self.args.adb, self.args.bob, "shell", "input", "keyevent", "26")
        run_adb(self.args.adb, self.args.bob, "shell", "wm", "dismiss-keyguard")
        time.sleep(3)
        after_lock = self.timer_seconds(self.b)
        same_after_lock = int(self.active_call().get("call_id", 0)) == int(
            active.get("call_id", 0)
        )
        lock_continued = after_lock >= before_lock + 6
        lock_evidence = evidence + self.b.snapshot("im313-after-lock-resume")
        if "IM-313" in selected:
            checks = {
                "call_id_unchanged": same_after_lock,
                "timer_before": before_lock,
                "timer_after": after_lock,
                "timer_continued": lock_continued,
                "both_still_connected": self.call_surface(self.a, True)
                and self.call_surface(self.b, True),
                "evidence": lock_evidence,
            }
            self.record(
                "IM-313",
                "PASS"
                if checks["call_id_unchanged"]
                and checks["timer_continued"]
                and checks["both_still_connected"]
                else "FAIL",
                checks,
            )

        before_home = self.timer_seconds(self.a)
        run_adb(self.args.adb, self.args.alice, "shell", "input", "keyevent", "3")
        time.sleep(8)
        self.a.device.app_start(self.args.package, stop=False, wait=True)
        time.sleep(3)
        after_home = self.timer_seconds(self.a)
        home_continued = after_home >= before_home + 6
        same_after_home = int(self.active_call().get("call_id", 0)) == int(
            active.get("call_id", 0)
        )
        home_evidence = self.a.snapshot("im314-after-background-resume")
        if "IM-314" in selected:
            checks = {
                "call_id_unchanged": same_after_home,
                "timer_before": before_home,
                "timer_after": after_home,
                "timer_continued": home_continued,
                "call_surface_restored": self.call_surface(self.a, True),
                "evidence": lock_evidence + home_evidence,
            }
            self.record(
                "IM-314",
                "PASS"
                if checks["call_id_unchanged"]
                and checks["timer_continued"]
                and checks["call_surface_restored"]
                else "FAIL",
                checks,
            )
        self.hang_up()

    def case_short_reconnect(self) -> None:
        active, evidence = self.start_call("voice")
        before = self.timer_seconds(self.a)
        self.set_wifi(self.args.bob, False)
        reconnect_visible = wait_until(
            lambda: "正在重连" in self.a.device.dump_hierarchy()
            or "正在重连" in self.b.device.dump_hierarchy(),
            timeout=35,
        )
        evidence += self.a.snapshot("im323-reconnecting-alice")
        evidence += self.b.snapshot("im323-reconnecting-bob")
        self.set_wifi(self.args.bob, True)
        recovered = wait_until(
            lambda: self.call_surface(self.a, True)
            and self.call_surface(self.b, True)
            and "正在重连" not in self.a.device.dump_hierarchy()
            and "正在重连" not in self.b.device.dump_hierarchy(),
            timeout=30,
        )
        after = self.timer_seconds(self.a)
        same_call = int(self.active_call().get("call_id", 0)) == int(
            active.get("call_id", 0)
        )
        evidence += self.a.snapshot("im323-recovered-alice")
        evidence += self.b.snapshot("im323-recovered-bob")
        checks = {
            "reconnecting_state_visible": reconnect_visible,
            "recovered_same_call": recovered and same_call,
            "timer_before": before,
            "timer_after": after,
            "timer_not_reset": after >= before,
            "evidence": evidence,
        }
        self.record(
            "IM-323",
            "PASS"
            if reconnect_visible
            and recovered
            and same_call
            and after >= before
            else "FAIL",
            checks,
        )
        self.hang_up()

    def case_long_disconnect(self) -> None:
        active, evidence = self.start_call("voice")
        self.set_wifi(self.args.bob, False)
        reconnect_visible = wait_until(
            lambda: "正在重连" in self.a.device.dump_hierarchy()
            or "正在重连" in self.b.device.dump_hierarchy(),
            timeout=35,
        )
        ended = wait_until(
            lambda: self.active_call().get("active") is not True,
            timeout=75,
        )
        evidence += self.a.snapshot("im324-alice-after-timeout")
        evidence += self.b.snapshot("im324-bob-after-timeout")
        self.set_wifi(self.args.bob, True)
        surfaces_closed = wait_until(
            lambda: not self.call_surface(self.a) and not self.call_surface(self.b),
            timeout=30,
        )
        redial = self.api.request(
            "POST",
            "/call/create",
            actor=self.alice,
            body={"target_user_id": self.bob.user_id, "call_type": "voice"},
        )
        redial_data = response_data(redial)
        redial_call_id = int(redial_data.get("call_id", 0)) if isinstance(redial_data, dict) else 0
        redial_succeeded = redial_call_id > 0
        if redial_succeeded:
            self.api.request(
                "POST",
                "/call/reject",
                actor=self.bob,
                body={"call_id": redial_call_id, "reason": "qa_cleanup"},
            )
        checks = {
            "initial_call_id": active.get("call_id"),
            "reconnecting_state_visible": reconnect_visible,
            "authoritative_call_ended": ended,
            "both_call_surfaces_closed": surfaces_closed,
            "immediate_redial_succeeded": redial_succeeded,
            "evidence": evidence,
        }
        self.record(
            "IM-324",
            "PASS"
            if reconnect_visible and ended and surfaces_closed and redial_succeeded
            else "FAIL",
            checks,
        )

    def case_offline_expiry(self) -> None:
        self.end_active_call()
        self.set_wifi(self.args.bob, False)
        run_adb(
            self.args.adb,
            self.args.bob,
            "shell",
            "am",
            "force-stop",
            self.args.package,
        )
        evidence = self.open_peer_profile(self.a, "Smoke Bob")
        started_at = time.monotonic()
        self.click_exact(self.a, "通话")
        self.dismiss_permissions(self.a)
        outgoing_visible = wait_until(lambda: self.call_surface(self.a), timeout=12)
        evidence += self.a.snapshot("im305-offline-outgoing")
        expired = wait_until(
            lambda: self.active_call().get("active") is not True
            and not self.call_surface(self.a),
            timeout=42,
        )
        elapsed = int(time.monotonic() - started_at)
        evidence += self.a.snapshot("im305-caller-expired")
        self.set_wifi(self.args.bob, True)
        self.b.device.app_start(self.args.package, stop=False, wait=True)
        self.dismiss_permissions(self.b)
        time.sleep(12)
        stale_incoming_absent = not (
            self.b.device(description="接听").exists(timeout=0.5)
            or self.b.device(text="接听").exists(timeout=0.5)
        )
        evidence += self.b.snapshot("im305-bob-restored-no-stale-call")
        checks = {
            "outgoing_surface_visible": outgoing_visible,
            "expired_without_answer": expired,
            "elapsed_seconds": elapsed,
            "expiry_within_expected_window": 25 <= elapsed <= 42,
            "no_stale_incoming_after_restore": stale_incoming_absent,
            "evidence": evidence,
        }
        self.record(
            "IM-305",
            "PASS"
            if outgoing_visible
            and expired
            and 25 <= elapsed <= 42
            and stale_incoming_absent
            else "FAIL",
            checks,
        )

    def case_simultaneous(self) -> None:
        self.end_active_call()
        for batch in (self.a, self.b):
            batch.device.app_start(self.args.package, stop=True, wait=True)
        time.sleep(4)
        evidence = self.open_peer_profile(self.a, "Smoke Bob")
        evidence += self.open_peer_profile(self.b, "Smoke Alice")
        barrier = threading.Barrier(3)
        errors: list[str] = []

        def tap(batch: MessageActionBatch) -> None:
            try:
                barrier.wait(timeout=5)
                self.click_exact(batch, "通话")
                self.dismiss_permissions(batch)
            except Exception as error:  # noqa: BLE001
                errors.append(str(error))

        threads = [
            threading.Thread(target=tap, args=(self.a,), daemon=True),
            threading.Thread(target=tap, args=(self.b,), daemon=True),
        ]
        for thread in threads:
            thread.start()
        barrier.wait(timeout=5)
        for thread in threads:
            thread.join(timeout=20)
        auto_arbitrated = wait_until(
            lambda: self.call_surface(self.a, True)
            and self.call_surface(self.b, True),
            timeout=8,
        )
        resolution_mode = "auto_arbitrated" if auto_arbitrated else ""
        if not auto_arbitrated:
            incoming = next(
                (
                    batch
                    for batch in (self.a, self.b)
                    if batch.device(description="接听").exists(timeout=0.5)
                    or batch.device(text="接听").exists(timeout=0.5)
                ),
                None,
            )
            if incoming is not None:
                self.click_exact(incoming, "接听")
                self.dismiss_permissions(incoming, timeout=15)
                resolution_mode = "single_incoming_accepted"
        connected = auto_arbitrated or wait_until(
            lambda: self.call_surface(self.a, True)
            and self.call_surface(self.b, True),
            timeout=25,
        )
        active_a = self.active_call(self.alice)
        active_b = self.active_call(self.bob)
        same_call = (
            active_a.get("active") is True
            and active_b.get("active") is True
            and int(active_a.get("call_id", 0)) == int(active_b.get("call_id", -1))
        )
        evidence += self.a.snapshot("im318-alice-arbitrated")
        evidence += self.b.snapshot("im318-bob-arbitrated")
        checks = {
            "tap_errors": errors,
            "both_connected": connected,
            "same_call_id": same_call,
            "resolution_mode": resolution_mode,
            "alice_call_id": active_a.get("call_id"),
            "bob_call_id": active_b.get("call_id"),
            "evidence": evidence,
        }
        self.record(
            "IM-318",
            "PASS" if not errors and connected and same_call else "FAIL",
            checks,
        )
        self.hang_up()

    def case_video(self, selected: set[str]) -> None:
        active, evidence = self.start_call("video")
        time.sleep(4)
        before_background = self.timer_seconds(self.b)
        run_adb(self.args.adb, self.args.bob, "shell", "input", "keyevent", "3")
        time.sleep(8)
        self.b.device.app_start(self.args.package, stop=False, wait=True)
        time.sleep(4)
        after_background = self.timer_seconds(self.b)
        video_restored = (
            self.b.device(description="摄像头已开").exists(timeout=1)
            or self.b.device(text="摄像头已开").exists(timeout=1)
        )
        same_call = int(self.active_call().get("call_id", 0)) == int(
            active.get("call_id", 0)
        )
        video_background_evidence = self.b.snapshot("im315-video-background-restored")
        if "IM-315" in selected:
            checks = {
                "call_id_unchanged": same_call,
                "timer_before": before_background,
                "timer_after": after_background,
                "timer_continued": after_background >= before_background + 6,
                "camera_restored": video_restored,
                "evidence": evidence + video_background_evidence,
            }
            self.record(
                "IM-315",
                "PASS"
                if same_call
                and checks["timer_continued"]
                and video_restored
                else "FAIL",
                checks,
            )

        self.click_button_exact(self.a, "摄像头已开")
        local_camera_off = wait_until(
            lambda: "摄像头已关" in self.a.device.dump_hierarchy(), timeout=8
        )
        remote_placeholder = wait_until(
            lambda: "对方已关闭摄像头" in self.b.device.dump_hierarchy(), timeout=12
        )
        camera_evidence = self.a.snapshot("im337-alice-camera-off")
        camera_evidence += self.b.snapshot("im337-bob-remote-camera-off")
        audio_continued = self.call_surface(self.a, True) and self.call_surface(
            self.b, True
        )
        self.click_button_exact(self.a, "摄像头已关")
        camera_restored = wait_until(
            lambda: "摄像头已开" in self.a.device.dump_hierarchy()
            and "对方已关闭摄像头" not in self.b.device.dump_hierarchy(),
            timeout=15,
        )
        camera_restored_evidence = self.a.snapshot("im337-alice-camera-restored")
        camera_restored_evidence += self.b.snapshot("im337-bob-remote-camera-restored")
        if "IM-337" in selected:
            checks = {
                "local_camera_off_visible": local_camera_off,
                "remote_camera_off_placeholder": remote_placeholder,
                "audio_call_continued": audio_continued,
                "camera_restored": camera_restored,
                "evidence": evidence
                + video_background_evidence
                + camera_evidence
                + camera_restored_evidence,
            }
            self.record(
                "IM-337",
                "PASS"
                if local_camera_off
                and remote_placeholder
                and audio_continued
                and camera_restored
                else "FAIL",
                checks,
            )

        before_downgrade = self.timer_seconds(self.a)
        self.click_exact(self.a, "更多")
        self.click_exact(self.a, "切换为语音通话")
        downgraded = wait_until(
            lambda: "语音通话" in self.a.device.dump_hierarchy()
            and "语音通话" in self.b.device.dump_hierarchy()
            and "摄像头已开" not in self.a.device.dump_hierarchy(),
            timeout=15,
        )
        after_downgrade = self.timer_seconds(self.a)
        downgrade_active = self.active_call()
        downgrade_evidence = self.a.snapshot("im308-alice-voice-downgrade")
        downgrade_evidence += self.b.snapshot("im308-bob-voice-downgrade")
        if "IM-308" in selected:
            checks = {
                "both_ui_downgraded_to_voice": downgraded,
                "timer_before": before_downgrade,
                "timer_after": after_downgrade,
                "timer_not_reset": after_downgrade >= before_downgrade,
                "same_call_id": int(downgrade_active.get("call_id", 0))
                == int(active.get("call_id", -1)),
                "evidence": evidence
                + video_background_evidence
                + camera_evidence
                + downgrade_evidence,
            }
            self.record(
                "IM-308",
                "PASS"
                if downgraded
                and checks["timer_not_reset"]
                and checks["same_call_id"]
                else "FAIL",
                checks,
            )
        self.hang_up()

    def run(self) -> dict[str, Any]:
        selected = set(self.args.only or CASES)
        try:
            self.setup()
            if selected & {"IM-313", "IM-314"}:
                self.case_lock_and_background(selected)
            if "IM-323" in selected:
                self.case_short_reconnect()
            if "IM-324" in selected:
                self.case_long_disconnect()
            if "IM-305" in selected:
                self.case_offline_expiry()
            if "IM-318" in selected:
                self.case_simultaneous()
            if selected & {"IM-308", "IM-315", "IM-337"}:
                self.case_video(selected)

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
            try:
                self.set_wifi(self.args.alice, True)
                self.set_wifi(self.args.bob, True)
            except Exception:
                pass
            self.end_active_call()
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
    parser.add_argument("--package", default="com.genericim.app")
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--only", action="append", choices=CASES)
    args = parser.parse_args()

    run_dir = Path(args.output_dir).resolve() / datetime.now().strftime(
        "%Y%m%d-%H%M%S"
    )
    run_dir.mkdir(parents=True, exist_ok=True)
    result = StrictCallUi(args, run_dir).run()
    return 0 if result["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
