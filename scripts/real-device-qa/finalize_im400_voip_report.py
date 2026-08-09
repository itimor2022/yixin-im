#!/usr/bin/env python3
"""Attach verified dual-device VoIP results to the IM-400 report."""

from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))
from run_im400_cross_account import load_cases  # noqa: E402
from run_im400_full import rel, set_case, write_report  # noqa: E402


def evidence(repo: Path, run_dir: Path, names: list[str]) -> list[str]:
    return [rel(run_dir / name, repo) for name in names]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", required=True)
    parser.add_argument("--run-dir", required=True)
    args = parser.parse_args()
    repo = Path(args.repo).resolve()
    run_dir = Path(args.run_dir).resolve()
    cases, payload = load_cases(run_dir / "results.json")
    a, b = "8MY0220C17006781", "UQG5T20915006269"

    ringing = evidence(repo, run_dir, [
        f"{a}-voip-retest-3s.png",
        f"{b}-voip-retest-3s.png",
        f"{a}-voip-retest-logcat.txt",
        f"{b}-voip-retest-logcat.txt",
    ])
    rejected = ringing + evidence(repo, run_dir, [
        f"{a}-voip-rejected.png",
        f"{a}-voip-rejected.xml",
        f"{b}-voip-rejected.png",
        f"{b}-voip-rejected.xml",
    ])
    cancelled = evidence(repo, run_dir, [
        f"{a}-voip-cancel-calling.png",
        f"{b}-voip-cancel-ringing.png",
        f"{a}-voip-cancel-after.png",
        f"{a}-voip-cancel-after.xml",
        f"{b}-voip-cancel-after.png",
        f"{b}-voip-cancel-after.xml",
        f"{a}-voip-cancel-logcat.txt",
        f"{b}-voip-cancel-logcat.txt",
    ])
    set_case(cases, "IM-301", "PASS", "A 在 B 在线时从私聊资料页发起一对一语音通话，并在 3 秒时优先截取 B 端。", "A 进入呼叫中；B 在 3 秒内显示来电页、来电通知以及拒绝/接听按钮。", ringing)
    set_case(cases, "IM-303", "PASS", "B 在来电页点击拒绝，并检查双方页面及会话记录。", "A 立即退出呼叫返回资料页；B 返回会话列表并生成语音通话已结束记录。", rejected)
    set_case(cases, "IM-306", "PASS", "再次发起语音通话，A 在 B 振铃期间主动取消。", "双方均退出通话 UI；B 生成语音通话已取消记录，旧邀请失效。", cancelled)

    summary = dict(payload.get("logcat_summary") or {})
    log_evidence = evidence(repo, run_dir, [
        f"{a}-voip-retest-logcat.txt", f"{b}-voip-retest-logcat.txt",
        f"{a}-voip-cancel-logcat.txt", f"{b}-voip-cancel-logcat.txt",
    ])
    summary["ended_at"] = datetime.now().astimezone().isoformat(timespec="seconds")
    summary["stop_reason"] = "cross-account-notification-and-voip-complete"
    summary["voip_logcat_evidence"] = log_evidence
    summary["analysis"] = "应用 PID 内的 Exception 均为华为 AGC 配置解密及设备缺少 GMS 的启动告警；跨账号私聊、后台通知、进程终止后的厂商通知、语音呼叫振铃、拒接及取消均成功，未出现 Crash/ANR/FATAL 或应用内 Socket 断连。"
    (run_dir / "combined-cross-notification-voip-logcat-summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
    environment = dict(payload.get("environment") or {})
    environment["dual_voip_verified"] = True
    write_report(repo, run_dir, cases, environment, summary)
    print(json.dumps({"summary": {status: sum(case.status == status for case in cases.values()) for status in ("PASS", "FAIL", "SKIP", "BLOCKED")}, "rows": len(cases)}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
