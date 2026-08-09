#!/usr/bin/env python3
"""Map completed favorite/reaction probes into an existing IM-400 report."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from run_im400_full import rel, set_case, write_report  # noqa: E402
from run_im400_message_actions import load_report  # noqa: E402


def latest_directory(run_dir: Path, pattern: str) -> Path:
    matches = sorted(
        (path for path in run_dir.glob(pattern) if path.is_dir()),
        key=lambda path: path.stat().st_mtime,
        reverse=True,
    )
    if not matches:
        raise RuntimeError(f"未找到证据目录：{pattern}")
    return matches[0]


def evidence(repo: Path, *paths: Path) -> list[str]:
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
    favorite = latest_directory(run_dir, "favorite-probe-*")
    reaction = latest_directory(run_dir, "reaction-probe-*")
    cases, environment, log_summary = load_report(run_dir)

    favorite_add = evidence(
        repo,
        favorite / "005-favorite-after.png",
        favorite / "005-favorite-after.xml",
        favorite / "001-favorites-page.png",
        favorite / "001-favorites-page.xml",
    )
    favorite_remove = evidence(
        repo,
        favorite / "001-favorite-remove-confirm.png",
        favorite / "001-favorite-remove-confirm.xml",
        favorite / "001-favorite-removed.png",
        favorite / "001-favorite-removed.xml",
        favorite / "002-favorite-original-retained.png",
        favorite / "002-favorite-original-retained.xml",
    )
    reaction_add = evidence(
        repo,
        reaction / "device-b" / "003-reaction-sent.png",
        reaction / "device-b" / "004-reaction-menu-1.png",
        reaction / "device-b" / "005-reaction-local-after.png",
        reaction / "device-a" / "002-reaction-correct-remote-after.png",
    )
    reaction_remove = evidence(
        repo,
        reaction / "cancel-b" / "002-reaction-cancel-menu-1.png",
        reaction / "cancel-b" / "003-reaction-cancel-local-after.png",
        reaction / "cancel-a" / "001-reaction-cancel-remote-after.png",
    )

    set_case(
        cases,
        "IM-136",
        "PASS",
        "B 机发送唯一文本并添加 👍 Reaction，A 机停留同一私聊实时核对。",
        "B 机立即显示一个 👍 回应，A 机收到同一消息后也实时显示一个 👍，回应内容与人数均一致。",
        reaction_add,
    )
    set_case(
        cases,
        "IM-137",
        "PASS",
        "B 机再次对同一消息点击自己的 👍 Reaction，随后同时核对 A、B 两端。",
        "自己的 👍 回应被取消，两端该消息下方的回应同时消失，消息正文保持不变。",
        reaction_remove,
    )
    set_case(
        cases,
        "IM-218",
        "BLOCKED",
        "发送唯一文本并长按收藏，再从聊天“+”附件面板进入收藏列表核对。",
        "文本收藏成功，收藏列表显示会话来源、发送者、时间与原文；图片、文件、链接类型尚未逐一覆盖。",
        favorite_add,
    )
    set_case(
        cases,
        "IM-219",
        "BLOCKED",
        "在收藏列表删除本轮文本收藏，再返回原会话核对。",
        "本机收藏已移除且原聊天消息保留；尚未使用同账号第二端验证多端同步。",
        favorite_remove,
    )

    write_report(repo, run_dir, cases, environment, log_summary)
    print(f"[MSG400] 已汇总收藏与 Reaction 证据：{favorite.name}, {reaction.name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
