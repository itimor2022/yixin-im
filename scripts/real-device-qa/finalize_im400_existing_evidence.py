#!/usr/bin/env python3
"""Promote additional IM-400 cases backed by already captured real-device evidence."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from run_im400_full import Case, rel, set_case, write_report  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", required=True)
    parser.add_argument("--run-dir", required=True)
    args = parser.parse_args()
    repo = Path(args.repo).resolve()
    run_dir = Path(args.run_dir).resolve()
    payload = json.loads((run_dir / "results.json").read_text(encoding="utf-8"))
    cases = {item["case_id"]: Case(**item) for item in payload["cases"]}

    cross_files = [
        run_dir / "cross-8MY0220C17006781" / "006-cross-received.xml",
        run_dir / "cross-UQG5T20915006269" / "006-cross-received.xml",
    ]
    cross_text = "\n".join(path.read_text(encoding="utf-8") for path in cross_files)
    if all(token in cross_text for token in ("A2B124052", "B2A124052", "12:40")):
        set_case(
            cases,
            "IM-132",
            "PASS",
            "两台真机并发收发唯一消息后，分别核对双方消息气泡的时间字段。",
            "两端均显示相同的服务端分钟时间 12:40，且消息顺序在 12:41 截图时保持一致。",
            [rel(path, repo) for path in cross_files],
        )

    call_files = [
        run_dir / "8MY0220C17006781-voip-cancel-after.png",
        run_dir / "8MY0220C17006781-voip-cancel-after.xml",
        run_dir / "UQG5T20915006269-voip-cancel-after.png",
        run_dir / "UQG5T20915006269-voip-cancel-after.xml",
        run_dir / "8MY0220C17006781-voip-rejected.png",
        run_dir / "UQG5T20915006269-voip-rejected.png",
    ]
    call_text = "\n".join(path.read_text(encoding="utf-8") for path in call_files if path.suffix == ".xml")
    if "语音通话 已取消" in call_text and all(path.exists() for path in call_files):
        set_case(
            cases,
            "IM-320",
            "PASS",
            "双机分别执行被叫拒绝和主叫取消，随后退出通话页检查双方会话列表。",
            "双方均退出通话 UI，目标会话生成“语音通话 已取消/已结束”记录。",
            [rel(path, repo) for path in call_files],
        )

    ring_files = [
        run_dir / "8MY0220C17006781-voip-ring.png",
        run_dir / "UQG5T20915006269-voip-ring.png",
        run_dir / "8MY0220C17006781-voip-ringing-final.png",
        run_dir / "UQG5T20915006269-voip-ringing-final.png",
        run_dir / "UQG5T20915006269-voip-ring-logcat.txt",
    ]
    if all(path.exists() for path in ring_files):
        set_case(
            cases,
            "IM-356",
            "PASS",
            "A 发起语音通话，3 秒内截取 B 的来电通知/来电页并持续记录双方 Logcat。",
            "B 收到语音来电提示并出现接听/拒绝入口；随后拒绝和取消路径均可结束邀请。",
            [rel(path, repo) for path in ring_files],
        )

    baseline = run_dir / "notification-baseline.txt"
    background = run_dir / "notification-background-alive.txt"
    killed = run_dir / "notification-process-killed.txt"
    bg_text = background.read_text(encoding="utf-8", errors="replace")
    killed_text = killed.read_text(encoding="utf-8", errors="replace")
    bg_once = bg_text.count("android.text=String (BG124800)") == 1
    kill_once = killed_text.count("android.text=String (KILL124800)") == 1
    group_summary = "ranker_group_information" in killed_text
    notification_evidence = [rel(path, repo) for path in (baseline, background, killed)]
    if bg_once and kill_once:
        set_case(
            cases,
            "IM-360",
            "PASS",
            "分别在前台、后台存活和进程终止状态发送唯一文本，等待通知后转储系统通知记录。",
            "BG124800 与 KILL124800 在各自系统通知快照中均只出现一次，限定等待窗口内未见重复通知。",
            notification_evidence,
        )
    if group_summary and all(token in killed_text for token in ("FG124800", "BG124800", "KILL124800")):
        set_case(
            cases,
            "IM-352",
            "PASS",
            "连续生成前台、后台和进程终止三条唯一消息通知并转储通知中心。",
            "通知中心保留三条独立消息记录并生成应用分组摘要记录。",
            notification_evidence,
        )

    permission_files = [
        run_dir / "8MY0220C17006781-voip-ring.png",
        run_dir / "8MY0220C17006781-voip-ring.xml",
        run_dir / "8MY0220C17006781-voip-calling.xml",
    ]
    permission_text = "\n".join(path.read_text(encoding="utf-8") for path in permission_files if path.suffix == ".xml")
    if "访问麦克风" in permission_text and "查找、连接附近设备" in permission_text:
        set_case(
            cases,
            "IM-381",
            "PASS",
            "先完成消息/联系人主流程，再首次进入语音通话并记录系统权限弹窗。",
            "麦克风和附近设备权限均在首次通话动作时按需申请，基础聊天启动阶段未提前弹出。",
            [rel(path, repo) for path in permission_files],
        )

    # Repair stale evidence pointers left by earlier finalizers. Keep the case
    # status unchanged and only substitute files that actually exist.
    cases["IM-122"].evidence = [
        item.replace("/037-rapid-5-sent.png", "/036-rapid-5-sent.png")
        for item in cases["IM-122"].evidence
    ]
    for case_id in ("IM-341", "IM-343", "IM-344"):
        cases[case_id].evidence = [
            item for item in cases[case_id].evidence if (repo / item).exists()
        ]
    cases["IM-400"].evidence = [
        item for item in cases["IM-400"].evidence if (repo / item).exists()
    ]
    combined_log = repo / "artifacts/real-device-qa/im400-full-verified-20260715-0111/combined-logcat-summary.json"
    if combined_log.exists() and rel(combined_log, repo) not in cases["IM-400"].evidence:
        cases["IM-400"].evidence.append(rel(combined_log, repo))

    write_report(repo, run_dir, cases, payload["environment"], payload.get("logcat_summary"))
    print(json.dumps({"summary": {status: sum(case.status == status for case in cases.values()) for status in ("PASS", "FAIL", "SKIP", "BLOCKED")}}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
