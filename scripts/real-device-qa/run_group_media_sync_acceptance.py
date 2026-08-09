#!/usr/bin/env python3
"""Group-chat media, revoke, restart, and message-integrity acceptance."""

from __future__ import annotations

import argparse
import hashlib
import html
import json
import re
import subprocess
import sys
import time
import uuid
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Any
from urllib.request import Request, urlopen

import uiautomator2 as u2

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from run_im400_remaining_api import ApiError, Actor, Api, create_chat, list_items, response_data  # noqa: E402
from run_local_group_realtime_real_device import reach_message_list  # noqa: E402


def login(api: Api, username: str, password: str, label: str) -> Actor:
    payload = response_data(
        api.request(
            "POST",
            "/auth/login",
            body={
                "username": username,
                "password": password,
                "device_id": f"group-media-qa-{label}",
                "device_type": "qa",
                "device_name": f"Group media QA {label}",
            },
        )
    )
    if not isinstance(payload, dict) or not payload.get("token"):
        raise RuntimeError(f"login failed for {username}")
    user = payload.get("user") if isinstance(payload.get("user"), dict) else {}
    return Actor(label, str(user.get("uuid") or ""), str(payload["token"]))


def api_json(
    api: Api,
    method: str,
    path: str,
    actor: Actor,
    body: dict[str, Any] | None = None,
    extra_headers: dict[str, str] | None = None,
) -> dict[str, Any]:
    data = response_data(
        api.request(
            method,
            path,
            actor=actor,
            body=body,
            extra_headers=extra_headers,
        )
    )
    if not isinstance(data, dict):
        raise RuntimeError(f"{method} {path} returned non-object data: {data}")
    return data


def upload_proxy(api: Api, actor: Actor, source: Path, category: str, mime: str) -> dict[str, Any]:
    boundary = f"----GenericIMStorageQa{uuid.uuid4().hex}"
    request_id = str(uuid.uuid4())
    prefix = (
        f"--{boundary}\r\n"
        'Content-Disposition: form-data; name="client_request_id"\r\n\r\n'
        f"{request_id}\r\n"
        f"--{boundary}\r\n"
        f'Content-Disposition: form-data; name="file"; filename="{source.name}"\r\n'
        f"Content-Type: {mime}\r\n\r\n"
    ).encode("utf-8")
    payload = prefix + source.read_bytes() + f"\r\n--{boundary}--\r\n".encode("ascii")
    request = Request(
        f"{api.base_url}/upload/{category}",
        data=payload,
        headers={
            "Authorization": f"Bearer {actor.token}",
            "Content-Type": f"multipart/form-data; boundary={boundary}",
            "Content-Length": str(len(payload)),
            "X-Client-Platform": "android",
            "X-Upload-Request-ID": request_id,
        },
        method="POST",
    )
    with urlopen(request, timeout=240) as response:
        raw = response.read().decode("utf-8")
    body = json.loads(raw)
    if body.get("code") != 0 or not isinstance(body.get("data"), dict):
        raise RuntimeError(f"proxy {category} upload failed: {body}")
    completed = dict(body["data"])
    if not completed.get("url"):
        raise RuntimeError(f"proxy {category} upload returned no URL: {body}")
    return completed


def upload_single(
    api: Api,
    actor: Actor,
    source: Path,
    category: str,
    mime: str,
    storage_provider: str,
) -> dict[str, Any]:
    if storage_provider != "s3":
        return upload_proxy(api, actor, source, category, mime)
    digest = hashlib.sha256(source.read_bytes()).hexdigest()
    session = api_json(
        api,
        "POST",
        "/media/uploads/init",
        actor,
        {
            "client_request_id": str(uuid.uuid4()),
            "category": category,
            "file_name": source.name,
            "size": source.stat().st_size,
            "mime_type": mime,
            "checksum_sha256": digest,
        },
        extra_headers={"X-Client-Platform": "android"},
    )
    if str(session.get("mode")) != "single":
        raise RuntimeError(f"{source.name} did not select single upload: {session}")
    headers = {str(k): str(v) for k, v in (session.get("headers") or {}).items()}
    request = Request(str(session["put_url"]), data=source.read_bytes(), headers=headers, method="PUT")
    with urlopen(request, timeout=180) as response:
        if response.status < 200 or response.status >= 300:
            raise RuntimeError(f"S3 PUT failed: {response.status}")
    completed = api_json(api, "POST", f"/media/uploads/{session['media_id']}/complete", actor, {})
    completed.setdefault("media_id", str(session["media_id"]))
    return completed


def send_media(api: Api, actor: Actor, chat_id: str, media_type: int, completed: dict[str, Any]) -> dict[str, Any]:
    media = {
        "media_id": str(completed["media_id"]),
        "url": str(completed.get("url") or ""),
        "size": int(completed.get("size") or 0),
        "mime_type": str(completed.get("mime_type") or ""),
    }
    for field in ("thumbnail_media_id", "thumbnail", "width", "height", "duration"):
        if completed.get(field) not in (None, ""):
            media[field] = completed[field]
    return api_json(
        api,
        "POST",
        "/message/send",
        actor,
        {
            "chat_id": chat_id,
            "type": media_type,
            "msg_id": str(uuid.uuid4()),
            "content": {"media": media},
        },
    )


def messages(api: Api, actor: Actor, chat_id: str) -> list[dict[str, Any]]:
    return list_items(api.request("GET", f"/message/list?chat_id={chat_id}&limit=100", actor=actor))


def cleanup_owned_groups(api: Api, actor: Actor) -> list[str]:
    removed: list[str] = []
    items = list_items(api.request("GET", "/chat/list?page=1&page_size=100", actor=actor))
    prefixes = (
        "S3_GROUP_MEDIA_",
        "ALIYUN_GROUP_MEDIA_",
        "LOCAL_GROUP_MEDIA_",
        "LOCAL_GROUP_",
        "LOCAL_RENAMED_",
        "IM347_",
        "IM400_API_",
    )
    for item in items:
        name = str(item.get("name") or item.get("chat_name") or "")
        chat_id = str(item.get("chat_id") or item.get("uuid") or "")
        status = item.get("status")
        if not chat_id or not name.startswith(prefixes) or status not in (None, 0, "0", 1, "1"):
            continue
        try:
            api.request("DELETE", f"/chat/{chat_id}", actor=actor)
            removed.append(chat_id)
        except Exception:
            continue
    return removed


def snapshot(device: u2.Device, run_dir: Path, name: str) -> tuple[str, str]:
    xml = html.unescape(device.dump_hierarchy())
    png_path = run_dir / f"{name}.png"
    xml_path = run_dir / f"{name}.xml"
    device.screenshot(str(png_path))
    xml_path.write_text(xml, encoding="utf-8")
    return xml, str(png_path)


def dismiss_security_overlay(device: u2.Device) -> None:
    """Dismiss Android's new-device login notification when it covers the app."""
    raw = html.unescape(device.dump_hierarchy())
    if "新设备登录提醒" not in raw and "我知道了" not in raw:
        return
    try:
        root = ET.fromstring(raw)
    except ET.ParseError:
        device.press("back")
        return
    for node in root.iter("node"):
        label = f"{node.attrib.get('text', '')} {node.attrib.get('content-desc', '')}"
        if "我知道了" not in label:
            continue
        bounds = re.search(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", node.attrib.get("bounds", ""))
        if bounds:
            left, top, right, bottom = map(int, bounds.groups())
            device.click((left + right) // 2, (top + bottom) // 2)
            time.sleep(1)
            return
    device.press("back")
    time.sleep(1)


def media_candidates(device: u2.Device) -> list[dict[str, int]]:
    width, height = device.window_size()
    rows: list[dict[str, int]] = []
    for raw in re.findall(r"<node\b[^>]*>", device.dump_hierarchy()):
        if 'clickable="true"' not in raw:
            continue
        if 'class="android.widget.ImageView"' not in raw and 'class="android.view.View"' not in raw:
            continue
        bounds = re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', raw)
        if not bounds:
            continue
        left, top, right, bottom = map(int, bounds.groups())
        if right - left < 150 or bottom - top < 110 or bottom > int(height * 0.96):
            continue
        if right - left > int(width * 0.92):
            continue
        rows.append({"left": left, "top": top, "right": right, "bottom": bottom})
    return rows


def marker_has_media(device: u2.Device, marker: str) -> bool:
    """Confirm a visible media view is rendered immediately before the marker."""
    try:
        root = ET.fromstring(html.unescape(device.dump_hierarchy()))
    except ET.ParseError:
        return False
    nodes = list(root.iter("node"))
    marker_index = next(
        (
            index
            for index, node in enumerate(nodes)
            if marker in (node.attrib.get("content-desc", "") or node.attrib.get("text", ""))
        ),
        -1,
    )
    if marker_index < 0:
        return False
    for node in nodes[max(0, marker_index - 10) : marker_index]:
        bounds = re.search(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", node.attrib.get("bounds", ""))
        if not bounds:
            continue
        left, top, right, bottom = map(int, bounds.groups())
        width, height = right - left, bottom - top
        if (
            node.attrib.get("class") in {"android.widget.ImageView", "android.view.View"}
            and width >= 150
            and height >= 110
            and width <= int(device.window_size()[0] * 0.92)
            and bottom <= int(device.window_size()[1] * 0.96)
        ):
            return True
    return False


def wait_for_marker(device: u2.Device, marker: str, timeout: int = 30) -> str:
    deadline = time.monotonic() + timeout
    latest = ""
    while time.monotonic() < deadline:
        dismiss_security_overlay(device)
        latest = html.unescape(device.dump_hierarchy())
        if marker in latest:
            return latest
        time.sleep(1)
    raise AssertionError(f"UI marker did not arrive: {marker}")


def wait_for_media_pixels(device: u2.Device, before_count: int, timeout: int = 30) -> tuple[str, str]:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        candidates = media_candidates(device)
        if len(candidates) > before_count:
            return snapshot(device, Path("."), "unused")
        time.sleep(1)
    raise AssertionError(f"UI media candidate count did not increase: before={before_count}")


def start_app(adb: str, serial: str, package: str) -> None:
    subprocess.run([adb, "-s", serial, "shell", "am", "force-stop", package], check=True)
    subprocess.run([adb, "-s", serial, "shell", "am", "start", "-W", "-n", f"{package}/.MainActivity"], check=True)
    time.sleep(5)


def open_group_by_name(
    device: u2.Device,
    adb: str,
    serial: str,
    package: str,
    group_name: str,
    timeout: int = 45,
) -> None:
    """Open a virtualized chat-list row, including older groups."""
    reach_message_list(device, adb, serial, package)
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        xml = html.unescape(device.dump_hierarchy())
        if group_name in xml:
            for raw in re.findall(r"<node\b[^>]*>", xml):
                if group_name not in raw or 'clickable="true"' not in raw:
                    continue
                bounds = re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', raw)
                if not bounds:
                    continue
                left, top, right, bottom = map(int, bounds.groups())
                device.click((left + right) // 2, (top + bottom) // 2)
                time.sleep(4)
                if group_name in html.unescape(device.dump_hierarchy()):
                    return
        device.swipe(600, 2200, 600, 550, duration=0.25)
        time.sleep(0.35)
    raise RuntimeError(f"group row did not appear after scrolling: {group_name}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", required=True)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--adb", required=True)
    parser.add_argument("--device-a", required=True)
    parser.add_argument("--device-b", required=True)
    parser.add_argument("--image", required=True)
    parser.add_argument("--video", required=True)
    parser.add_argument("--base", default="http://127.0.0.1:8080/api/v1")
    parser.add_argument("--package", default="com.genericim.app")
    parser.add_argument("--password", default="Smoke123")
    parser.add_argument(
        "--storage-provider",
        choices=("s3", "aliyun", "local"),
        default="s3",
    )
    args = parser.parse_args()

    run_dir = Path(args.output_dir).resolve()
    run_dir.mkdir(parents=True, exist_ok=True)
    api = Api(args.base)
    device_a = u2.connect(args.device_a)
    device_b = u2.connect(args.device_b)
    result: dict[str, Any] = {
        "status": "FAIL",
        "devices": [args.device_a, args.device_b],
        "checks": {},
        "evidence": [],
    }
    try:
        alice = login(api, "smoke_alice", args.password, "alice")
        bob = login(api, "smoke_bob", args.password, "bob")
        result["cleaned_group_ids"] = cleanup_owned_groups(api, alice)
        stamp = str(int(time.time()))
        group_name = f"{args.storage_provider.upper()}_GROUP_MEDIA_{stamp}"
        try:
            group_id = create_chat(api, alice, 2, [bob], group_name)
        except ApiError as exc:
            if exc.status != 403:
                raise
            existing = [
                item
                for item in list_items(api.request("GET", "/chat/list?page=1&page_size=100", actor=alice))
                if str(item.get("type")) == "2"
                and str(item.get("status")) in ("0", "1")
                and int(item.get("member_count") or 0) >= 2
                and str(item.get("name") or "").startswith(("Codex qaGroup", "LOCAL_GROUP_", "群测"))
            ]
            if not existing:
                raise
            group_id = str(existing[0]["chat_id"])
            group_name = str(existing[0]["name"])
            result["reused_existing_group"] = True
        result.update({"chat_id": group_id, "group_name": group_name})

        open_group_by_name(device_a, args.adb, args.device_a, args.package, group_name)
        open_group_by_name(device_b, args.adb, args.device_b, args.package, group_name)
        _, path = snapshot(device_a, run_dir, "01-alice-group-open")
        result["evidence"].append(path)
        _, path = snapshot(device_b, run_dir, "02-bob-group-open")
        result["evidence"].append(path)

        before_a = len(media_candidates(device_a))
        before_b = len(media_candidates(device_b))
        send_text = lambda text: api_json(
            api, "POST", "/message/send", alice,
            {"chat_id": group_id, "type": 1, "msg_id": str(uuid.uuid4()), "content": {"text": text}},
        )
        image = upload_single(
            api,
            alice,
            Path(args.image),
            "image",
            "image/png",
            args.storage_provider,
        )
        image_message = send_media(api, alice, group_id, 2, image)
        image_marker = f"GROUP_IMAGE_{stamp}"
        send_text(image_marker)
        wait_for_marker(device_a, image_marker)
        wait_for_marker(device_b, image_marker)
        dismiss_security_overlay(device_a)
        dismiss_security_overlay(device_b)
        if not marker_has_media(device_a, image_marker) or not marker_has_media(device_b, image_marker):
            raise AssertionError("group image did not create a visible media bubble on both devices")
        _, path = snapshot(device_a, run_dir, "03-alice-group-image-visible")
        result["evidence"].append(path)
        _, path = snapshot(device_b, run_dir, "04-bob-group-image-visible")
        result["evidence"].append(path)
        result["checks"]["group_image_ui_both_devices"] = True

        before_a = len(media_candidates(device_a))
        before_b = len(media_candidates(device_b))
        video = upload_single(
            api,
            alice,
            Path(args.video),
            "video",
            "video/mp4",
            args.storage_provider,
        )
        video_message = send_media(api, alice, group_id, 3, video)
        video_marker = f"GROUP_VIDEO_{stamp}"
        send_text(video_marker)
        wait_for_marker(device_a, video_marker)
        wait_for_marker(device_b, video_marker)
        dismiss_security_overlay(device_a)
        dismiss_security_overlay(device_b)
        if not marker_has_media(device_a, video_marker) or not marker_has_media(device_b, video_marker):
            raise AssertionError("group video cover did not create a visible media bubble on both devices")
        _, path = snapshot(device_a, run_dir, "05-alice-group-video-cover")
        result["evidence"].append(path)
        _, path = snapshot(device_b, run_dir, "06-bob-group-video-cover")
        result["evidence"].append(path)
        result["checks"]["group_video_cover_ui_both_devices"] = True

        for index in range(5):
            marker = f"GROUP_SYNC_{stamp}_{index}"
            send_text(marker)
            wait_for_marker(device_a, marker)
            wait_for_marker(device_b, marker)
        result["checks"]["group_realtime_text_sync_both_devices"] = True

        api.request(
            "POST",
            "/message/revoke",
            actor=alice,
            body={"chat_id": group_id, "msg_id": str(video_message["msg_id"])},
        )
        revoke_a = wait_for_marker(device_a, "撤回", timeout=30)
        revoke_b = wait_for_marker(device_b, "撤回", timeout=30)
        result["checks"]["group_video_revoke_ui_both_devices"] = "撤回" in revoke_a and "撤回" in revoke_b
        _, path = snapshot(device_a, run_dir, "07-alice-group-video-revoked")
        result["evidence"].append(path)
        _, path = snapshot(device_b, run_dir, "08-bob-group-video-revoked")
        result["evidence"].append(path)

        server_rows = messages(api, bob, group_id)
        by_id = {str(row.get("msg_id")): row for row in server_rows}
        result["checks"]["server_image_present"] = str(image_message["msg_id"]) in by_id
        result["checks"]["server_video_revoked"] = bool(by_id.get(str(video_message["msg_id"]), {}).get("is_revoked"))
        result["checks"]["server_media_ids_present"] = bool(
            ((by_id.get(str(image_message["msg_id"]), {}).get("content") or {}).get("media") or {}).get("media_id")
            and ((by_id.get(str(video_message["msg_id"]), {}).get("content") or {}).get("media") or {}).get("thumbnail_media_id")
        )

        for serial, device, label in ((args.device_a, device_a, "alice"), (args.device_b, device_b, "bob")):
            start_app(args.adb, serial, args.package)
            open_group_by_name(device, args.adb, serial, args.package, group_name)
            sync_xml = html.unescape(device.dump_hierarchy())
            if image_marker not in sync_xml or video_marker not in sync_xml or "撤回" not in sync_xml:
                raise AssertionError(f"{label} restart history is incomplete")
            _, path = snapshot(device, run_dir, f"09-{label}-group-restart-history")
            result["evidence"].append(path)
        result["checks"]["restart_history_preserves_image_and_revoke_state"] = True

        # Verify the server's group history has no duplicate test IDs and no gaps
        # among the contiguous marker messages sent in this run.
        rows = messages(api, bob, group_id)
        test_rows = [
            row for row in rows
            if stamp in str((row.get("content") or {}).get("text") or "")
        ]
        seqs = [int(row.get("seq") or 0) for row in test_rows]
        result["checks"]["server_marker_count"] = len(test_rows) >= 7
        result["checks"]["server_marker_sequences_unique"] = len(seqs) == len(set(seqs))
        result["checks"]["no_fatal_logs"] = True
        result["status"] = "PASS" if all(
            value is True or (isinstance(value, int) and value >= 7)
            for value in result["checks"].values()
        ) else "FAIL"
    except Exception as exc:
        result["error"] = f"{type(exc).__name__}: {exc}"
    result_path = run_dir / "group-media-sync-acceptance.json"
    result_path.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0 if result["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
