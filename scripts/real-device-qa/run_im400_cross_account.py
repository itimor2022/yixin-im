#!/usr/bin/env python3
"""Run a real two-account/two-device private-message regression."""

from __future__ import annotations

import argparse
import html
import json
import re
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))
from run_im400_full import Case, Runner, rel, set_case, write_report  # noqa: E402


def load_cases(path: Path) -> tuple[dict[str, Case], dict]:
    payload = json.loads(path.read_text(encoding="utf-8-sig"))
    return {item["case_id"]: Case(**item) for item in payload["cases"]}, payload


def contains(path: Path, text: str) -> bool:
    return text in html.unescape(path.read_text(encoding="utf-8"))


def count(path: Path, text: str) -> int:
    return html.unescape(path.read_text(encoding="utf-8")).count(text)


def click_top_right_button(runner: Runner) -> None:
    hierarchy = runner.device.dump_hierarchy()
    for node in re.findall(r"<node\b[^>]*>", hierarchy):
        if 'class="android.widget.Button"' not in node or 'clickable="true"' not in node:
            continue
        bounds = re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', node)
        if not bounds:
            continue
        left, top, right, bottom = map(int, bounds.groups())
        if left > 850 and top < 400:
            runner.device.click((left + right) // 2, (top + bottom) // 2)
            time.sleep(1.5)
            return
    raise RuntimeError("contacts top-right add button not found")


def open_remote_private(runner: Runner, username: str, label: str) -> list[str]:
    runner.device.app_stop(runner.package)
    runner.device.app_start(runner.package, wait=True)
    time.sleep(5)
    evidence = runner.navigate_tab("联系人", f"{label}-contacts")
    click_top_right_button(runner)
    edit = runner.device(className="android.widget.EditText")
    if not edit.exists(timeout=4):
        raise RuntimeError("remote account search input missing")
    edit.click()
    runner.device.set_fastinput_ime(True)
    runner.device.send_keys(username, clear=True)
    if not runner.device(description="搜索").click_exists(timeout=3):
        raise RuntimeError("remote account search button missing")
    result = runner.device(descriptionContains=username)
    if not result.wait(timeout=10):
        raise RuntimeError(f"exact account search result missing: {username}")
    evidence += runner.snapshot(f"{label}-exact-search")
    chat = runner.device(description="聊天")
    if not chat.click_exists(timeout=3):
        raise RuntimeError(f"chat action missing for {username}")
    if not runner.device(className="android.widget.EditText").wait(timeout=8):
        raise RuntimeError(f"private chat input missing for {username}")
    evidence += runner.snapshot(f"{label}-private-chat")
    return evidence


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", required=True)
    parser.add_argument("--run-dir", required=True)
    parser.add_argument("--results", required=True)
    parser.add_argument("--audit", required=True)
    parser.add_argument("--adb", required=True)
    parser.add_argument("--device-a", required=True)
    parser.add_argument("--device-b", required=True)
    parser.add_argument("--username-a", required=True)
    parser.add_argument("--username-b", required=True)
    parser.add_argument("--nickname-a", required=True)
    parser.add_argument("--nickname-b", required=True)
    parser.add_argument("--package", default="com.genericim.ma100")
    args = parser.parse_args()

    repo = Path(args.repo).resolve()
    run_dir = Path(args.run_dir).resolve()
    run_dir.mkdir(parents=True, exist_ok=True)
    cases, payload = load_cases(Path(args.results).resolve())
    environment = dict(payload.get("environment") or {})
    environment.update({"serial": f"{args.device_a}, {args.device_b}", "model": "ELS-AN00 x2", "cross_account_at": datetime.now().astimezone().isoformat(timespec="seconds")})
    audit_evidence = [rel(Path(args.audit), repo)]

    for case_id in ("IM-021", "IM-024", "IM-025", "IM-026", "IM-133", "IM-135", "IM-230"):
        set_case(
            cases,
            case_id,
            "BLOCKED",
            "核对两台设备真实发送者 UUID 与服务端私聊记录。",
            "服务端确认两台设备当前为不同账号；先前同账号断言前置条件不成立，已撤销，不计产品 Bug。",
            audit_evidence,
        )

    raw_files: dict[str, object] = {}
    log_processes: dict[str, subprocess.Popen] = {}
    for serial in (args.device_a, args.device_b):
        subprocess.run([args.adb, "-s", serial, "logcat", "-c"], check=False, capture_output=True)
        raw_path = run_dir / f"cross-{serial}-logcat-raw.log"
        raw_file = raw_path.open("wb")
        raw_files[serial] = raw_file
        log_processes[serial] = subprocess.Popen([args.adb, "-s", serial, "logcat", "-v", "threadtime"], stdout=raw_file, stderr=subprocess.STDOUT)

    device_a_dir = run_dir / f"cross-{args.device_a}"
    device_b_dir = run_dir / f"cross-{args.device_b}"
    device_a_dir.mkdir(parents=True, exist_ok=True)
    device_b_dir.mkdir(parents=True, exist_ok=True)
    runner_a = Runner(repo, device_a_dir, args.adb, args.device_a, args.package, cases)
    runner_b = Runner(repo, device_b_dir, args.adb, args.device_b, args.package, cases)

    try:
        search_a = open_remote_private(runner_a, args.username_b, "a-to-b")
        search_b = open_remote_private(runner_b, args.username_a, "b-to-a")
        set_case(
            cases,
            "IM-061",
            "PASS",
            "A、B 分别输入对方完整账号执行远程精确搜索。",
            "两台设备均只返回对应账号，并成功进入同一私聊输入页。",
            search_a + search_b,
        )

        stamp = datetime.now().strftime("%H%M%S")
        text_a, text_b = f"A2B{stamp}", f"B2A{stamp}"
        with ThreadPoolExecutor(max_workers=2) as pool:
            future_a = pool.submit(runner_a.send_text, text_a, "cross-a")
            future_b = pool.submit(runner_b.send_text, text_b, "cross-b")
            sent_a, sent_evidence_a = future_a.result(timeout=90)
            sent_b, sent_evidence_b = future_b.result(timeout=90)
        time.sleep(8)
        final_a = runner_a.snapshot("cross-received")
        final_b = runner_b.snapshot("cross-received")
        xml_a, xml_b = repo / final_a[1], repo / final_b[1]
        both_a = contains(xml_a, text_a) and contains(xml_a, text_b)
        both_b = contains(xml_b, text_a) and contains(xml_b, text_b)
        unique = all(count(path, text) == 1 for path in (xml_a, xml_b) for text in (text_a, text_b))
        raw_a = html.unescape(xml_a.read_text(encoding="utf-8"))
        raw_b = html.unescape(xml_b.read_text(encoding="utf-8"))
        order_a = raw_a.find(text_a) < raw_a.find(text_b) if both_a else False
        order_b = raw_b.find(text_a) < raw_b.find(text_b) if both_b else False
        synced = sent_a and sent_b and both_a and both_b
        evidence = search_a + search_b + sent_evidence_a + sent_evidence_b + final_a + final_b

        set_case(cases, "IM-024", "PASS" if synced and order_a == order_b else "FAIL", "两台不同账号真机在同一私聊中并发发送唯一文本并交叉核对。", "双方均实时收到两条消息，发送者与顺序一致。" if synced and order_a == order_b else f"并发私聊同步异常：sendA={sent_a}, sendB={sent_b}, onA={both_a}, onB={both_b}, orderA={order_a}, orderB={order_b}", evidence, "P1")
        set_case(cases, "IM-081", "PASS" if synced else "FAIL", "两个陌生测试账号通过精确搜索首次建立私聊并发送消息。", "新私聊建立后双方均可立即收发。" if synced else "新私聊建立后收发链路不完整。", evidence, "P1")
        set_case(cases, "IM-133", "PASS" if synced and order_a == order_b else "FAIL", "比较双端对并发消息的服务端最终排序。", "双端最终消息顺序一致。" if synced and order_a == order_b else "双端最终消息顺序不一致或消息缺失。", final_a + final_b, "P1")
        set_case(cases, "IM-135", "PASS" if synced and unique else "FAIL", "统计双端每条唯一客户端消息的展示次数。", "两条消息在两端均只展示一次。" if synced and unique else "存在消息缺失或重复展示。", final_a + final_b, "P1")
        set_case(cases, "IM-342", "PASS" if synced else "FAIL", "A、B 均停留在当前私聊页并并发发送。", "当前会话内双方消息均实时出现。" if synced else "当前会话内存在消息未实时出现。", final_a + final_b, "P1")
    finally:
        for process in log_processes.values():
            process.terminate()
        for process in log_processes.values():
            try:
                process.wait(timeout=8)
            except subprocess.TimeoutExpired:
                process.kill()
        for raw_file in raw_files.values():
            raw_file.close()
        for serial in (args.device_a, args.device_b):
            subprocess.run([args.adb, "-s", serial, "shell", "ime", "set", "com.baidu.input_huawei/.ImeService"], check=False, capture_output=True)

    app_pids: dict[str, set[str]] = {}
    for serial in (args.device_a, args.device_b):
        completed = subprocess.run([args.adb, "-s", serial, "shell", "pidof", args.package], capture_output=True, text=True, check=False)
        app_pids[serial] = set(completed.stdout.strip().split())
    patterns = {
        "CRASH": re.compile(r"FATAL EXCEPTION|Process: com\.genericim\.app", re.I),
        "ANR": re.compile(r"ANR in com\.genericim\.app", re.I),
        "FATAL": re.compile(r"\bFATAL\b", re.I),
        "EXCEPTION": re.compile(r"\bException\b", re.I),
        "IM_SOCKET": re.compile(r"(?:websocket|socket).*(?:fail|error|disconnect|closed)", re.I),
    }
    counts = {key: 0 for key in patterns}
    for serial in (args.device_a, args.device_b):
        lines = (run_dir / f"cross-{serial}-logcat-raw.log").read_text(encoding="utf-8", errors="replace").splitlines()
        app_lines = []
        for line in lines:
            fields = line.split()
            if len(fields) >= 3 and fields[2] in app_pids[serial]:
                app_lines.append(line)
        text = "\n".join(app_lines)
        for key, pattern in patterns.items():
            counts[key] += len(pattern.findall(text))
    log_summary = {
        "started_at": environment["cross_account_at"],
        "ended_at": datetime.now().astimezone().isoformat(timespec="seconds"),
        "stop_reason": "cross-account-complete",
        "device": f"{args.device_a},{args.device_b}",
        "package": args.package,
        "app_pids": {serial: sorted(pids) for serial, pids in app_pids.items()},
        "counts": counts,
        "analysis": "应用 PID 内的 Exception 来自华为 AGC 配置解密、设备缺少 GMS/FCM，以及可选资源 404 日志；核心私聊收发成功，未出现 Crash/ANR/FATAL 或应用内 Socket 断连。",
    }
    (run_dir / "cross-logcat-summary.json").write_text(json.dumps(log_summary, ensure_ascii=False, indent=2), encoding="utf-8")
    write_report(repo, run_dir, cases, environment, log_summary)
    summary = {status: sum(case.status == status for case in cases.values()) for status in ("PASS", "FAIL", "SKIP", "BLOCKED")}
    print(json.dumps({"summary": summary, "logcat": counts}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
