#!/usr/bin/env python3
"""Exercise foreground/background/killed-process private-message delivery."""

from __future__ import annotations

import argparse
import html
import json
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))
from run_im400_cross_account import load_cases, open_remote_private  # noqa: E402
from run_im400_full import Runner, rel, set_case, write_report  # noqa: E402


def shell(adb: str, serial: str, *args: str) -> str:
    completed = subprocess.run([adb, "-s", serial, *args], capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=45, check=False)
    return completed.stdout + completed.stderr


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", required=True)
    parser.add_argument("--run-dir", required=True)
    parser.add_argument("--results", required=True)
    parser.add_argument("--adb", required=True)
    parser.add_argument("--device-a", required=True)
    parser.add_argument("--device-b", required=True)
    parser.add_argument("--username-a", required=True)
    parser.add_argument("--username-b", required=True)
    parser.add_argument("--package", default="com.genericim.app")
    args = parser.parse_args()

    repo = Path(args.repo).resolve()
    run_dir = Path(args.run_dir).resolve()
    cases, payload = load_cases(Path(args.results).resolve())
    environment = dict(payload.get("environment") or {})
    environment["notification_cross_at"] = datetime.now().astimezone().isoformat(timespec="seconds")
    a_dir, b_dir = run_dir / f"notify-{args.device_a}", run_dir / f"notify-{args.device_b}"
    a_dir.mkdir(parents=True, exist_ok=True)
    b_dir.mkdir(parents=True, exist_ok=True)
    a = Runner(repo, a_dir, args.adb, args.device_a, args.package, cases)
    b = Runner(repo, b_dir, args.adb, args.device_b, args.package, cases)

    open_a = open_remote_private(a, args.username_b, "notify-a-to-b")
    open_b = open_remote_private(b, args.username_a, "notify-b-to-a")
    list_b = b.navigate_tab("消息", "receiver-message-list")
    stamp = datetime.now().strftime("%H%M%S")

    foreground_text = f"FG{stamp}"
    sent_fg, evidence_fg = a.send_text(foreground_text, "foreground-list")
    time.sleep(6)
    received_fg = b.snapshot("foreground-list-received")
    fg_xml = repo / received_fg[1]
    fg_visible = foreground_text in html.unescape(fg_xml.read_text(encoding="utf-8"))
    set_case(
        cases,
        "IM-341",
        "PASS" if sent_fg and fg_visible else "FAIL",
        "B 保持 App 前台但停留消息列表，A 从私聊发送唯一文本。",
        "消息列表实时出现新消息预览，未打断当前页面。" if sent_fg and fg_visible else "前台非当前会话未实时出现消息预览。",
        open_a + open_b + list_b + evidence_fg + received_fg,
        "P1",
    )

    baseline = shell(args.adb, args.device_b, "shell", "dumpsys", "notification", "--noredact")
    (run_dir / "notification-baseline.txt").write_text(baseline, encoding="utf-8")
    b.device.press("home")
    time.sleep(2)
    background_text = f"BG{stamp}"
    sent_bg, evidence_bg = a.send_text(background_text, "background-alive")
    time.sleep(10)
    background_dump = shell(args.adb, args.device_b, "shell", "dumpsys", "notification", "--noredact")
    background_path = run_dir / "notification-background-alive.txt"
    background_path.write_text(background_dump, encoding="utf-8")
    bg_notified = args.package in background_dump and (background_text in background_dump or background_dump.count(args.package) > baseline.count(args.package))
    set_case(
        cases,
        "IM-343",
        "PASS" if sent_bg and bg_notified else "FAIL",
        "B 回到系统桌面但保留 App 进程，A 发送唯一文本并检查系统通知服务记录。",
        "后台存活时收到该消息对应的系统通知记录。" if sent_bg and bg_notified else "后台存活时未发现该消息对应的系统通知记录。",
        evidence_bg + [rel(background_path, repo)],
        "P1",
    )

    shell(args.adb, args.device_b, "shell", "am", "kill", args.package)
    time.sleep(2)
    killed_text = f"KILL{stamp}"
    sent_killed, evidence_killed = a.send_text(killed_text, "receiver-process-killed")
    time.sleep(18)
    killed_dump = shell(args.adb, args.device_b, "shell", "dumpsys", "notification", "--noredact")
    killed_path = run_dir / "notification-process-killed.txt"
    killed_path.write_text(killed_dump, encoding="utf-8")
    killed_notified = args.package in killed_dump and (killed_text in killed_dump or killed_dump.count(args.package) > background_dump.count(args.package))
    if sent_killed and killed_notified:
        set_case(cases, "IM-344", "PASS", "B 在后台由系统 am kill 终止进程，A 发送唯一文本并等待厂商推送。", "进程终止后仍生成该消息对应的通知记录。", evidence_killed + [rel(killed_path, repo)])
    else:
        set_case(cases, "IM-344", "SKIP", "B 在后台由系统 am kill 终止进程，A 发送唯一文本并等待厂商推送。", "未收到离线厂商通知；本机启动日志存在华为 AGC 配置解密告警，无法确认完整厂商推送配置，按要求不将未配置链路判为 Bug。", evidence_killed + [rel(killed_path, repo)])

    for serial in (args.device_a, args.device_b):
        shell(args.adb, serial, "shell", "ime", "set", "com.baidu.input_huawei/.ImeService")
    previous_log = payload.get("logcat_summary")
    write_report(repo, run_dir, cases, environment, previous_log)
    summary = {status: sum(case.status == status for case in cases.values()) for status in ("PASS", "FAIL", "SKIP", "BLOCKED")}
    print(json.dumps({"summary": summary, "foreground": fg_visible, "background_notification": bg_notified, "killed_notification": killed_notified}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
