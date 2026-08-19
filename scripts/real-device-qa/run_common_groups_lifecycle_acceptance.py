#!/usr/bin/env python3
"""Validate common-group creation and dissolution on API and two Android devices."""

from __future__ import annotations

import argparse
import html
import json
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import Any, Callable


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
    list_items,
    response_data,
)
from run_local_group_realtime_real_device import app_fatal_lines, login  # noqa: E402


def wait_until(
    predicate: Callable[[], bool],
    *,
    timeout: int = 15,
    interval: float = 0.7,
) -> bool:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if predicate():
            return True
        time.sleep(interval)
    return False


def common_state(api: Api, actor: Actor, peer: Actor) -> dict[str, Any]:
    groups_data = response_data(
        api.request("GET", f"/user/{peer.user_id}/common-groups", actor=actor)
    )
    info_data = response_data(
        api.request("GET", f"/user/{peer.user_id}/common-info", actor=actor)
    )
    if not isinstance(groups_data, dict) or not isinstance(
        groups_data.get("groups"), list
    ):
        raise RuntimeError(f"invalid common-groups response: {groups_data}")
    if not isinstance(info_data, dict):
        raise RuntimeError(f"invalid common-info response: {info_data}")
    groups = groups_data["groups"]
    return {
        "groups": groups,
        "group_ids": [str(item.get("id") or "") for item in groups],
        "total": int(groups_data.get("total", len(groups))),
        "common_group_count": int(info_data.get("common_group_count", -1)),
    }


def ensure_contact(api: Api, actor: Actor, peer: Actor) -> None:
    contacts = list_items(
        api.request("GET", "/contact/list?page=1&page_size=200", actor=actor)
    )
    if any(str(item.get("uuid") or item.get("id") or "") == peer.user_id for item in contacts):
        return
    api.request(
        "POST",
        "/contact/add",
        actor=actor,
        body={"user_id": peer.user_id},
    )


def click_node(batch: MessageActionBatch, node: dict[str, Any]) -> None:
    batch.device.click(
        (node["left"] + node["right"]) // 2,
        (node["top"] + node["bottom"]) // 2,
    )
    time.sleep(1.2)


def create_group_on_device(
    api: Api,
    owner: Actor,
    peer: Actor,
    batch: MessageActionBatch,
    group_name: str,
    peer_name: str,
    peer_username: str,
) -> tuple[str, list[str]]:
    restart_on_messages(batch)
    width, height = batch.device.window_size()
    create_option_buttons = [
        item
        for item in batch._nodes()
        if item["clickable"]
        and item["left"] > int(width * 0.72)
        and item["top"] < int(height * 0.16)
        and item["bottom"] > item["top"]
    ]
    if not create_option_buttons:
        raise RuntimeError("top-right create button is missing")
    click_node(
        batch,
        min(
            create_option_buttons,
            key=lambda row: max(1, row["right"] - row["left"])
            * max(1, row["bottom"] - row["top"]),
        ),
    )
    if not wait_until(
        lambda: "新建群组" in html.unescape(batch.device.dump_hierarchy()),
        timeout=8,
    ):
        raise RuntimeError("create options did not open on the real device")

    rows = [
        item
        for item in batch._nodes()
        if item["clickable"] and "新建群组" in f"{item['desc']} {item['text']}"
    ]
    if not rows:
        raise RuntimeError("new-group action is missing")
    click_node(batch, rows[0])

    if not wait_until(
        lambda: batch.device(className="android.widget.EditText").count >= 2,
        timeout=10,
    ):
        raise RuntimeError("new-group form did not open")
    refresh = batch.device(description="刷新好友")
    if refresh.exists(timeout=1):
        refresh.click()
        time.sleep(1.5)
    edit_fields = batch.device(className="android.widget.EditText")
    edit_fields[0].click()
    batch.device.send_keys(group_name, clear=True)
    time.sleep(2)
    if batch.device(className="android.widget.EditText").count < 2:
        raise RuntimeError("new-group form closed while entering the group name")

    member_rows: list[dict[str, Any]] = []
    for _ in range(8):
        member_rows = [
            item
            for item in batch._nodes()
            if item["clickable"]
            and item["bottom"] > item["top"]
            and "在线" in item["desc"]
            and peer_name in f"{item['desc']} {item['text']}"
        ]
        if member_rows:
            break
        batch.device.swipe(
            width // 2,
            int(height * 0.90),
            width // 2,
            int(height * 0.67),
            duration=0.45,
        )
        time.sleep(0.6)
    if not member_rows:
        raise RuntimeError(
            f"group member is missing from friend selector: {peer_name} ({peer_username})"
        )
    click_node(batch, member_rows[0])

    create_rows: list[dict[str, Any]] = []
    for _ in range(8):
        create_rows = [
            item
            for item in batch._nodes()
            if item["clickable"] and item["desc"].strip() == "创建"
        ]
        if create_rows:
            break
        time.sleep(0.5)
    if not create_rows:
        raise RuntimeError("create-group submit button did not become enabled")
    click_node(batch, create_rows[0])

    group_id = ""
    for _ in range(30):
        state = common_state(api, owner, peer)
        matching = [
            item for item in state["groups"] if str(item.get("name") or "") == group_name
        ]
        if matching:
            group_id = str(matching[0].get("id") or "")
            break
        time.sleep(0.7)
    if not group_id:
        raise RuntimeError("real-device group creation did not reach the common-groups API")

    if not wait_until(
        lambda: group_name in html.unescape(batch.device.dump_hierarchy()),
        timeout=12,
    ):
        raise RuntimeError("new group chat did not become visible on the creating device")
    return group_id, batch.snapshot("group-created-on-device")


def open_peer_profile(
    batch: MessageActionBatch,
    peer_name: str,
) -> list[str]:
    evidence = batch.open_chat(peer_name)
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
    click_node(
        batch,
        max(
            matches,
            key=lambda row: max(1, row["right"] - row["left"])
            * max(1, row["bottom"] - row["top"]),
        ),
    )
    if not wait_until(
        lambda: "共同群聊" in html.unescape(batch.device.dump_hierarchy())
        or "共同群组" in html.unescape(batch.device.dump_hierarchy()),
        timeout=12,
    ):
        raise RuntimeError(f"peer profile common-group section missing: {peer_name}")
    return evidence + batch.snapshot("peer-profile")


def open_common_group_list(
    batch: MessageActionBatch,
    expected_group_name: str,
) -> tuple[bool, list[str]]:
    width, height = batch.device.window_size()
    for _ in range(8):
        rows = [
            item
            for item in batch._nodes()
            if item["clickable"]
            and (
                "共同群聊" in f"{item['desc']} {item['text']}"
                or "共同群组" in f"{item['desc']} {item['text']}"
            )
        ]
        if rows:
            click_node(batch, rows[0])
            break
        batch.device.swipe(
            width // 2,
            int(height * 0.80),
            width // 2,
            int(height * 0.38),
            duration=0.5,
        )
        time.sleep(0.6)
    else:
        raise RuntimeError("common-group entry was not clickable")

    evidence = batch.snapshot("common-groups-opened")
    if expected_group_name in html.unescape(batch.device.dump_hierarchy()):
        return True, evidence

    # Common groups are returned in database order; a newly-created group is
    # normally at the end. Scan down the real list instead of trusting one frame.
    previous = ""
    for index in range(20):
        xml = html.unescape(batch.device.dump_hierarchy())
        if expected_group_name in xml:
            evidence += batch.snapshot(f"common-group-found-{index:02d}")
            return True, evidence
        descriptions = "\n".join(
            item["desc"] for item in batch._nodes() if item["desc"]
        )
        if descriptions == previous:
            break
        previous = descriptions
        batch.device.swipe(
            width // 2,
            int(height * 0.80),
            width // 2,
            int(height * 0.30),
            duration=0.45,
        )
        time.sleep(0.5)
    evidence += batch.snapshot("common-groups-list-end")
    return False, evidence


def restart_on_messages(batch: MessageActionBatch) -> None:
    batch.device.app_start(batch.package, stop=True, wait=True)
    time.sleep(4)
    batch.ensure_messages()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", default=".")
    parser.add_argument("--adb", required=True)
    parser.add_argument("--alice-device", required=True)
    parser.add_argument("--bob-device", required=True)
    parser.add_argument("--base", default="http://127.0.0.1:8080/api/v1")
    parser.add_argument("--password", default="Smoke123")
    parser.add_argument("--package", default="com.genericim.ma100")
    parser.add_argument("--creator", choices=("alice", "bob"), default="bob")
    parser.add_argument("--output-dir", required=True)
    args = parser.parse_args()

    repo = Path(args.repo).resolve()
    output_dir = Path(args.output_dir).resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    alice_dir = output_dir / "alice"
    bob_dir = output_dir / "bob"
    alice_dir.mkdir(exist_ok=True)
    bob_dir.mkdir(exist_ok=True)

    result: dict[str, Any] = {
        "status": "FAIL",
        "generated_at": datetime.now().astimezone().isoformat(timespec="seconds"),
        "base": args.base,
        "devices": {
            "alice": args.alice_device,
            "bob": args.bob_device,
        },
        "checks": {},
        "evidence_dir": str(output_dir),
    }

    api = Api(args.base.rstrip("/"))
    alice = login(api, "smoke_alice", args.password, "common-groups-alice")
    bob = login(api, "smoke_bob", args.password, "common-groups-bob")
    a = MessageActionBatch(repo, alice_dir, args.alice_device, args.package)
    b = MessageActionBatch(repo, bob_dir, args.bob_device, args.package)

    group_id = ""
    group_name = f"COMMON_LIFECYCLE_{datetime.now().strftime('%H%M%S')}"
    if args.creator == "alice":
        creator, invitee, creator_batch = alice, bob, a
        creator_peer_name, creator_peer_username = "Smoke Bob", "smoke_bob"
    else:
        creator, invitee, creator_batch = bob, alice, b
        creator_peer_name, creator_peer_username = "Smoke Alice", "smoke_alice"
    try:
        for serial in (args.alice_device, args.bob_device):
            subprocess.run(
                [args.adb, "-s", serial, "logcat", "-c"],
                check=False,
                capture_output=True,
            )

        baseline_a = common_state(api, alice, bob)
        baseline_b = common_state(api, bob, alice)
        ensure_contact(api, alice, bob)
        ensure_contact(api, bob, alice)
        group_id, creation_evidence = create_group_on_device(
            api,
            creator,
            invitee,
            creator_batch,
            group_name,
            creator_peer_name,
            creator_peer_username,
        )

        created_a = common_state(api, alice, bob)
        created_b = common_state(api, bob, alice)
        api_created_visible = all(
            group_id in state["group_ids"] for state in (created_a, created_b)
        )
        api_created_counted = (
            created_a["common_group_count"]
            == baseline_a["common_group_count"] + 1
            and created_b["common_group_count"]
            == baseline_b["common_group_count"] + 1
            and created_a["total"] == baseline_a["total"] + 1
            and created_b["total"] == baseline_b["total"] + 1
        )
        if not api_created_visible or not api_created_counted:
            raise AssertionError("created group is missing or counts did not increase")

        restart_on_messages(a)
        restart_on_messages(b)
        created_ui: dict[str, Any] = {}
        for label, batch, peer_name in (
            ("alice", a, "Smoke Bob"),
            ("bob", b, "Smoke Alice"),
        ):
            evidence = open_peer_profile(batch, peer_name)
            found, list_evidence = open_common_group_list(batch, group_name)
            created_ui[label] = {
                "group_visible": found,
                "evidence": evidence + list_evidence,
            }
            if not found:
                raise AssertionError(
                    f"{label} real-device common-group list does not show {group_name}"
                )

        api.request("DELETE", f"/chat/{group_id}", actor=creator)
        dissolved_a = common_state(api, alice, bob)
        dissolved_b = common_state(api, bob, alice)
        api_dissolved_hidden = all(
            group_id not in state["group_ids"] for state in (dissolved_a, dissolved_b)
        )
        api_counts_restored = (
            dissolved_a["common_group_count"] == baseline_a["common_group_count"]
            and dissolved_b["common_group_count"] == baseline_b["common_group_count"]
            and dissolved_a["total"] == baseline_a["total"]
            and dissolved_b["total"] == baseline_b["total"]
        )
        if not api_dissolved_hidden or not api_counts_restored:
            raise AssertionError("dissolved group remains visible or counts did not restore")

        restart_on_messages(a)
        restart_on_messages(b)
        dissolved_ui: dict[str, Any] = {}
        for label, batch, peer_name in (
            ("alice", a, "Smoke Bob"),
            ("bob", b, "Smoke Alice"),
        ):
            evidence = open_peer_profile(batch, peer_name)
            found, list_evidence = open_common_group_list(batch, group_name)
            dissolved_ui[label] = {
                "group_hidden": not found,
                "evidence": evidence + list_evidence,
            }
            if found:
                raise AssertionError(
                    f"{label} real-device common-group list still shows {group_name}"
                )

        fatal_lines: dict[str, list[str]] = {}
        for label, serial in (
            ("alice", args.alice_device),
            ("bob", args.bob_device),
        ):
            log_path = output_dir / f"{label}-logcat.txt"
            completed = subprocess.run(
                [args.adb, "-s", serial, "logcat", "-d", "-v", "threadtime"],
                check=False,
                capture_output=True,
                text=True,
                encoding="utf-8",
                errors="replace",
            )
            log_path.write_text(completed.stdout, encoding="utf-8")
            fatal_lines[label] = app_fatal_lines(
                args.adb,
                serial,
                args.package,
            )

        result["checks"] = {
            "baseline": {"alice": baseline_a, "bob": baseline_b},
            "created_api": {
                "alice": created_a,
                "bob": created_b,
                "visible_both_directions": api_created_visible,
                "counts_incremented": api_created_counted,
            },
            "created_real_device": created_ui,
            "creation_real_device": {
                "group_created": True,
                "evidence": creation_evidence,
            },
            "dissolved_api": {
                "alice": dissolved_a,
                "bob": dissolved_b,
                "hidden_both_directions": api_dissolved_hidden,
                "counts_restored": api_counts_restored,
            },
            "dissolved_real_device": dissolved_ui,
            "fatal_lines": fatal_lines,
        }
        if any(fatal_lines.values()):
            raise AssertionError(f"fatal application log lines found: {fatal_lines}")

        result["status"] = "PASS"
    except Exception as error:  # noqa: BLE001
        result["error"] = str(error)
    finally:
        # If the run failed before the planned dissolve, only clean up the
        # uniquely-created group owned by the QA account.
        if group_id:
            try:
                api.request("DELETE", f"/chat/{group_id}", actor=creator)
            except Exception:
                pass
        (output_dir / "results.json").write_text(
            json.dumps(result, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )

    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0 if result["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
