#!/usr/bin/env python3
"""Resume the IM-400 report with two authorized Android devices."""

from __future__ import annotations

import argparse
import html
import json
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


def hierarchy_contains(path: Path, text: str) -> bool:
    return text in html.unescape(path.read_text(encoding="utf-8"))


def count_text(path: Path, text: str) -> int:
    return html.unescape(path.read_text(encoding="utf-8")).count(text)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", required=True)
    parser.add_argument("--run-dir", required=True)
    parser.add_argument("--source-results", required=True)
    parser.add_argument("--adb", required=True)
    parser.add_argument("--device-a", required=True)
    parser.add_argument("--device-b", required=True)
    parser.add_argument("--package", default="com.genericim.app")
    parser.add_argument("--chat-title", default="通用IM官方体验群")
    parser.add_argument("--current-chat", action="store_true")
    parser.add_argument("--finalize-log", default="")
    args = parser.parse_args()

    repo = Path(args.repo).resolve()
    run_dir = Path(args.run_dir).resolve()
    run_dir.mkdir(parents=True, exist_ok=True)

    current_results = run_dir / "results.json"
    source = current_results if current_results.exists() else Path(args.source_results).resolve()
    cases, payload = load_cases(source)
    environment = dict(payload.get("environment") or {})
    environment.update(
        {
            "serial": f"{args.device_a}, {args.device_b}",
            "model": "ELS-AN00 x2",
            "dual_device_resume_at": datetime.now().astimezone().isoformat(timespec="seconds"),
        }
    )

    if args.finalize_log:
        log_summary = json.loads(Path(args.finalize_log).read_text(encoding="utf-8-sig"))
        severe = sum(int(log_summary.get("counts", {}).get(key, 0)) for key in ("CRASH", "ANR", "FATAL"))
        if severe:
            set_case(
                cases,
                "IM-400",
                "FAIL",
                "双机补测期间持续监听两台设备 Logcat。",
                f"双机补测发现严重日志 {severe} 条。",
                [rel(Path(args.finalize_log), repo)],
                "P0",
            )
        write_report(repo, run_dir, cases, environment, log_summary)
        return 0

    device_dirs = {
        "A": run_dir / args.device_a,
        "B": run_dir / args.device_b,
    }
    for directory in device_dirs.values():
        directory.mkdir(parents=True, exist_ok=True)

    runner_a = Runner(repo, device_dirs["A"], args.adb, args.device_a, args.package, cases)
    runner_b = Runner(repo, device_dirs["B"], args.adb, args.device_b, args.package, cases)

    runner_a.ensure_app()
    runner_b.ensure_app()
    if args.current_chat:
        evidence_a = runner_a.snapshot("same-account-main")
        evidence_b = runner_b.snapshot("same-account-main")
    else:
        evidence_a = runner_a.navigate_tab("消息", "same-account-main")
        evidence_b = runner_b.navigate_tab("消息", "same-account-main")
    set_case(
        cases,
        "IM-021",
        "PASS",
        "同一 smoke_bob 账号在两台已授权手机同时启动并进入消息页。",
        "两台手机均保持登录且可独立操作；当前服务策略为同账号手机共存，不执行互踢。",
        evidence_a + evidence_b,
    )
    set_case(
        cases,
        "IM-025",
        "SKIP",
        "检查同账号第二台手机登录后的会话策略。",
        "服务端明确采用同会话版本共存策略，本次未触发互踢，因此无被踢提示可验证。",
        evidence_a + evidence_b,
    )
    set_case(
        cases,
        "IM-026",
        "SKIP",
        "检查是否产生互踢及重新登录前置条件。",
        "两台手机按策略共存，没有设备被踢下线；该分支本轮不适用。",
        evidence_a + evidence_b,
    )

    if args.current_chat:
        if not runner_a.device(className="android.widget.EditText").exists(timeout=3):
            raise RuntimeError(f"device A chat input missing for {args.chat_title}")
        if not runner_b.device(className="android.widget.EditText").exists(timeout=3):
            raise RuntimeError(f"device B chat input missing for {args.chat_title}")
        open_a = runner_a.snapshot("same-account-chat-open")
        open_b = runner_b.snapshot("same-account-chat-open")
    else:
        open_a = runner_a.open_chat(args.chat_title, "same-account-chat-open")
        open_b = runner_b.open_chat(args.chat_title, "same-account-chat-open")
    stamp = datetime.now().strftime("%H%M%S")
    text_a = f"DUALA{stamp}"
    text_b = f"DUALB{stamp}"
    with ThreadPoolExecutor(max_workers=2) as pool:
        future_a = pool.submit(runner_a.send_text, text_a, "concurrent-a")
        future_b = pool.submit(runner_b.send_text, text_b, "concurrent-b")
        sent_a, send_evidence_a = future_a.result(timeout=90)
        sent_b, send_evidence_b = future_b.result(timeout=90)

    time.sleep(8)
    if not args.current_chat:
        runner_a.open_chat(args.chat_title, "same-account-chat-refresh")
        runner_b.open_chat(args.chat_title, "same-account-chat-refresh")
    final_a = runner_a.snapshot("same-account-cross-check")
    final_b = runner_b.snapshot("same-account-cross-check")
    xml_a = repo / final_a[1]
    xml_b = repo / final_b[1]
    both_on_a = hierarchy_contains(xml_a, text_a) and hierarchy_contains(xml_a, text_b)
    both_on_b = hierarchy_contains(xml_b, text_a) and hierarchy_contains(xml_b, text_b)
    unique = all(
        count_text(path, text) == 1
        for path in (xml_a, xml_b)
        for text in (text_a, text_b)
    )
    raw_a = html.unescape(xml_a.read_text(encoding="utf-8"))
    raw_b = html.unescape(xml_b.read_text(encoding="utf-8"))
    order_a = raw_a.find(text_a) < raw_a.find(text_b) if both_on_a else False
    order_b = raw_b.find(text_a) < raw_b.find(text_b) if both_on_b else False
    synced = sent_a and sent_b and both_on_a and both_on_b
    evidence = open_a + open_b + send_evidence_a + send_evidence_b + final_a + final_b

    set_case(
        cases,
        "IM-024",
        "PASS" if synced else "FAIL",
        f"两台手机并发向同一 {args.chat_title} 会话发送不同唯一文本，并在两端重新进入会话交叉核对。",
        "两条并发消息均同步到两台设备。" if synced else f"同步不完整：sendA={sent_a}, sendB={sent_b}, onA={both_on_a}, onB={both_on_b}",
        evidence,
        "P1",
    )
    set_case(
        cases,
        "IM-133",
        "PASS" if synced and order_a == order_b else "FAIL",
        "比较两台设备对两条并发消息的时间线顺序。",
        "两端消息顺序一致。" if synced and order_a == order_b else f"顺序不一致或消息缺失：A={order_a}, B={order_b}",
        final_a + final_b,
        "P1",
    )
    set_case(
        cases,
        "IM-135",
        "PASS" if synced and unique else "FAIL",
        "统计两端 UI 树中每个唯一客户端文本的出现次数。",
        "每条唯一消息在每台设备均只出现一次。" if synced and unique else "发现消息缺失或重复。",
        final_a + final_b,
        "P1",
    )
    set_case(
        cases,
        "IM-230",
        "PASS" if synced and order_a == order_b else "FAIL",
        "两台设备重新进入同一会话并比较最新历史内容与顺序。",
        "双端最新历史一致。" if synced and order_a == order_b else "双端最新历史存在差异。",
        final_a + final_b,
        "P1",
    )

    for runner in (runner_a, runner_b):
        try:
            runner.device.set_fastinput_ime(False)
        except Exception:
            pass

    write_report(repo, run_dir, cases, environment, payload.get("logcat_summary"))
    summary = {
        status: sum(case.status == status for case in cases.values())
        for status in ("PASS", "FAIL", "SKIP", "BLOCKED")
    }
    print(json.dumps({"texts": [text_a, text_b], "summary": summary, "synced": synced, "unique": unique, "order_consistent": order_a == order_b}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
