#!/usr/bin/env python3
"""Small uiautomator2 command driver for repeatable Android real-device QA."""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path
from typing import Any

import uiautomator2 as u2


def emit(payload: dict[str, Any], exit_code: int = 0) -> None:
    print(json.dumps(payload, ensure_ascii=False, indent=2))
    raise SystemExit(exit_code)


def selector(device: Any, kind: str, value: str, contains: bool) -> Any:
    if kind == "text":
        return device(textContains=value) if contains else device(text=value)
    if kind == "description":
        return (
            device(descriptionContains=value)
            if contains
            else device(description=value)
        )
    if kind == "resource-id":
        return device(resourceId=value)
    raise ValueError(f"unsupported selector kind: {kind}")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--serial", required=True, help="ADB device serial")
    parser.add_argument("--package", default="com.genericim.app")
    sub = parser.add_subparsers(dest="action", required=True)

    sub.add_parser("probe")
    sub.add_parser("start")
    sub.add_parser("stop")

    press = sub.add_parser("press")
    press.add_argument("key", choices=["back", "home", "recent", "menu", "enter", "delete"])

    tap = sub.add_parser("tap")
    tap.add_argument("x", type=int)
    tap.add_argument("y", type=int)

    long_press = sub.add_parser("long-press")
    long_press.add_argument("x", type=int)
    long_press.add_argument("y", type=int)
    long_press.add_argument("--duration", type=float, default=1.0)

    swipe = sub.add_parser("swipe")
    swipe.add_argument("x1", type=int)
    swipe.add_argument("y1", type=int)
    swipe.add_argument("x2", type=int)
    swipe.add_argument("y2", type=int)
    swipe.add_argument("--duration", type=float, default=0.3)

    type_text = sub.add_parser("type")
    type_text.add_argument("text")
    type_text.add_argument("--clear", action="store_true")

    for name in ("tap-selector", "wait-selector", "exists-selector"):
        command = sub.add_parser(name)
        command.add_argument("kind", choices=["text", "description", "resource-id"])
        command.add_argument("value")
        command.add_argument("--contains", action="store_true")
        command.add_argument("--timeout", type=float, default=10.0)

    screenshot = sub.add_parser("screenshot")
    screenshot.add_argument("path")

    dump_ui = sub.add_parser("dump-ui")
    dump_ui.add_argument("path")

    snapshot = sub.add_parser("snapshot")
    snapshot.add_argument("directory")
    snapshot.add_argument("--name", default="snapshot")

    wait_idle = sub.add_parser("wait-idle")
    wait_idle.add_argument("--seconds", type=float, default=1.0)
    return parser


def main() -> None:
    args = build_parser().parse_args()
    started = time.monotonic()
    try:
        device = u2.connect(args.serial)
        action = args.action

        if action == "probe":
            payload = {
                "ok": True,
                "serial": args.serial,
                "package": args.package,
                "deviceInfo": device.info,
                "windowSize": device.window_size(),
                "currentApp": device.app_current(),
            }
        elif action == "start":
            device.app_start(args.package, stop=False, wait=True)
            payload = {"ok": True, "currentApp": device.app_current()}
        elif action == "stop":
            device.app_stop(args.package)
            payload = {"ok": True, "package": args.package}
        elif action == "press":
            device.press(args.key)
            payload = {"ok": True, "key": args.key}
        elif action == "tap":
            device.click(args.x, args.y)
            payload = {"ok": True, "point": [args.x, args.y]}
        elif action == "long-press":
            device.long_click(args.x, args.y, duration=args.duration)
            payload = {
                "ok": True,
                "point": [args.x, args.y],
                "duration": args.duration,
            }
        elif action == "swipe":
            device.swipe(args.x1, args.y1, args.x2, args.y2, duration=args.duration)
            payload = {
                "ok": True,
                "from": [args.x1, args.y1],
                "to": [args.x2, args.y2],
                "duration": args.duration,
            }
        elif action == "type":
            device.send_keys(args.text, clear=args.clear)
            payload = {"ok": True, "characters": len(args.text), "cleared": args.clear}
        elif action in {"tap-selector", "wait-selector", "exists-selector"}:
            node = selector(device, args.kind, args.value, args.contains)
            exists = bool(node.wait(timeout=args.timeout))
            if action == "tap-selector" and exists:
                node.click()
            payload = {
                "ok": exists,
                "selector": {
                    "kind": args.kind,
                    "value": args.value,
                    "contains": args.contains,
                },
                "action": action,
            }
            if not exists:
                emit(payload, 2)
        elif action == "screenshot":
            path = Path(args.path).resolve()
            path.parent.mkdir(parents=True, exist_ok=True)
            device.screenshot(str(path))
            payload = {"ok": path.is_file(), "screenshot": str(path)}
        elif action == "dump-ui":
            path = Path(args.path).resolve()
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(device.dump_hierarchy(), encoding="utf-8")
            payload = {"ok": path.is_file(), "hierarchy": str(path)}
        elif action == "snapshot":
            directory = Path(args.directory).resolve()
            directory.mkdir(parents=True, exist_ok=True)
            png = directory / f"{args.name}.png"
            xml = directory / f"{args.name}.xml"
            device.screenshot(str(png))
            xml.write_text(device.dump_hierarchy(), encoding="utf-8")
            payload = {
                "ok": png.is_file() and xml.is_file(),
                "screenshot": str(png),
                "hierarchy": str(xml),
                "currentApp": device.app_current(),
            }
        elif action == "wait-idle":
            time.sleep(args.seconds)
            payload = {"ok": True, "waitedSeconds": args.seconds}
        else:
            raise ValueError(f"unsupported action: {action}")

        payload["elapsedMs"] = round((time.monotonic() - started) * 1000)
        emit(payload)
    except SystemExit:
        raise
    except Exception as exc:  # The CLI must return structured evidence on tool failures.
        emit(
            {
                "ok": False,
                "serial": args.serial,
                "action": args.action,
                "errorType": type(exc).__name__,
                "error": str(exc),
                "elapsedMs": round((time.monotonic() - started) * 1000),
            },
            1,
        )


if __name__ == "__main__":
    main()
