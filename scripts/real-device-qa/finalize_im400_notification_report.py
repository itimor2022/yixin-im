#!/usr/bin/env python3
"""Attach notification-run Logcat evidence and regenerate the IM-400 report."""

from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))
from run_im400_cross_account import load_cases  # noqa: E402
from run_im400_full import rel, write_report  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", required=True)
    parser.add_argument("--run-dir", required=True)
    args = parser.parse_args()
    repo = Path(args.repo).resolve()
    run_dir = Path(args.run_dir).resolve()
    results = run_dir / "results.json"
    cases, payload = load_cases(results)
    log_paths = [
        run_dir / "notify-8MY0220C17006781-logcat-buffer.log",
        run_dir / "notify-UQG5T20915006269-logcat-buffer.log",
    ]
    log_evidence = [rel(path, repo) for path in log_paths]
    for case_id in ("IM-341", "IM-343", "IM-344"):
        for item in log_evidence:
            if item not in cases[case_id].evidence:
                cases[case_id].evidence.append(item)

    summary = dict(payload.get("logcat_summary") or {})
    summary["ended_at"] = datetime.now().astimezone().isoformat(timespec="seconds")
    summary["stop_reason"] = "cross-account-and-notification-complete"
    summary["notification_logcat_evidence"] = log_evidence
    summary["analysis"] = "应用 PID 内的 Exception 均为华为 AGC 配置解密及设备缺少 GMS 的启动告警；跨账号私聊、后台通知和进程终止后的厂商通知均成功，未出现 Crash/ANR/FATAL 或应用内 Socket 断连。"
    summary_path = run_dir / "combined-cross-notification-logcat-summary.json"
    summary_path.write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
    environment = dict(payload.get("environment") or {})
    environment["notification_logcat_captured"] = True
    write_report(repo, run_dir, cases, environment, summary)
    print(json.dumps({"summary": {status: sum(case.status == status for case in cases.values()) for status in ("PASS", "FAIL", "SKIP", "BLOCKED")}, "rows": len(cases)}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
