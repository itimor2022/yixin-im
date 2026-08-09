#!/usr/bin/env python3
"""Apply visually reviewed conclusions from the latest dual-state batch."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from run_im400_full import rel, set_case, write_report  # noqa: E402
from run_im400_message_actions import load_report  # noqa: E402


def latest_directory(run_dir: Path) -> Path:
    matches = sorted(
        (
            path
            for path in run_dir.glob("dual-message-states-*")
            if path.is_dir()
            and (path / "device-a" / "008-scrolled-history-before-new.png").exists()
        ),
        key=lambda path: path.stat().st_mtime,
        reverse=True,
    )
    if not matches:
        raise RuntimeError("未找到 dual-message-states 证据目录")
    return matches[0]


def checked(repo: Path, *paths: Path) -> list[str]:
    missing = [str(path) for path in paths if not path.exists()]
    if missing:
        raise RuntimeError(f"证据文件缺失：{missing}")
    return [rel(path, repo) for path in paths]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", required=True)
    parser.add_argument("--run-dir", required=True)
    args = parser.parse_args()

    repo = Path(args.repo).resolve()
    run_dir = Path(args.run_dir).resolve()
    root = latest_directory(run_dir)
    a = root / "device-a"
    b = root / "device-b"
    cases, environment, log_summary = load_report(run_dir)

    scroll_evidence = checked(
        repo,
        a / "008-scrolled-history-before-new.png",
        a / "008-scrolled-history-before-new.xml",
        a / "009-scrolled-history-after-new.png",
        a / "009-scrolled-history-after-new.xml",
        b / "009-scroll-new-sent.png",
        b / "009-scroll-new-sent.xml",
    )
    receipt_evidence = checked(
        repo,
        b / "005-receipt-delivered-before-read.png",
        b / "005-receipt-delivered-before-read.xml",
        a / "005-receipt-unread-in-list.png",
        a / "005-receipt-unread-in-list.xml",
        a / "006-chat-opened.png",
        a / "006-chat-opened.xml",
        b / "006-receipt-read-after-open.png",
        b / "006-receipt-read-after-open.xml",
    )

    set_case(
        cases,
        "IM-120",
        "PASS",
        "A 端连续上翻到历史位置后，B 端发送唯一文本；同时区分系统通知与 App 内消息气泡。",
        "A 端保持原历史阅读位置，没有强制跳到底部；右下角回到底部按钮持续显示。顶部仅出现系统通知横幅。",
        scroll_evidence,
    )
    set_case(
        cases,
        "IM-126",
        "FAIL",
        "A 端在线停留会话列表，B 端发送唯一文本；先核对送达状态，再由 A 打开会话核对已读状态。",
        "A 端在线收到消息并显示未读，但 B 端此时仍为单勾发送状态，未更新为双勾已送达；A 打开会话后才直接变为绿色双勾已读。",
        receipt_evidence,
        "P2",
    )
    set_case(
        cases,
        "IM-128",
        "PASS",
        "A 端仅停留会话列表、不进入消息详情，B 端发送唯一文本。",
        "A 端会话预览出现唯一文本并保持未读；B 端仍显示单勾，明确没有在消息实际曝光前误报已读。",
        receipt_evidence,
    )

    write_report(repo, run_dir, cases, environment, log_summary)
    print(f"[STATE400] 已应用视觉复核结论：{root.name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
