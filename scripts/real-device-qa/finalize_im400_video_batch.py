#!/usr/bin/env python3
"""Apply visually reviewed IM-400 video conclusions to the active report."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from run_im400_full import rel, set_case, write_report  # noqa: E402
from run_im400_message_actions import load_report  # noqa: E402


def checked(repo: Path, *paths: Path) -> list[str]:
    missing = [str(path) for path in paths if not path.exists()]
    if missing:
        raise RuntimeError(f"证据文件缺失：{missing}")
    return [rel(path, repo) for path in paths]


def require_text(path: Path, *needles: str) -> None:
    text = path.read_text(encoding="utf-8", errors="replace")
    missing = [needle for needle in needles if needle not in text]
    if missing:
        raise RuntimeError(f"证据断言失败：{path} 未包含 {missing}")


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", required=True)
    parser.add_argument("--run-dir", required=True)
    args = parser.parse_args()

    repo = Path(args.repo).resolve()
    run_dir = Path(args.run_dir).resolve()
    video = run_dir / "video-batch"
    album_b = video / "device-b-album"
    album_a = video / "device-a-album"
    playback = video / "device-a-playback"
    camera_b = video / "device-b-camera"
    camera_a = video / "device-a-camera"
    fixture = video / "fixtures" / "short-landscape.mp4"
    cases, environment, log_summary = load_report(run_dir)

    require_text(album_b / "003-video-filter-search.xml", "IM400-short-landscape.mp4", "4.37 MB", "MP4")
    require_text(album_b / "004-video-sender-settled.xml", "4.2 MB", "19:37")
    require_text(album_a / "001-video-receiver.xml", "4.2 MB", "19:37")
    require_text(camera_b / "003-video-recording-5s.xml", "00:09", "完成")
    require_text(camera_b / "005-video-recorded-preview.xml", "61%", "19:41")
    require_text(camera_b / "006-camera-video-sender-settled.xml", "Retry send", "19:41")
    require_text(camera_b / "007-camera-video-retry-result.xml", "Retry send", "19:41")

    seeked = playback / "003-video-seeked.png"
    forced_landscape = playback / "004-video-landscape.png"
    if digest(seeked) != digest(forced_landscape):
        raise RuntimeError("强制横屏截图不再与竖屏截图一致，需重新视觉复核 IM-186")

    set_case(
        cases,
        "IM-181",
        "PASS",
        "将受控横屏 MP4 推送至 B 端 Download 并完成媒体索引；从聊天相册的视频筛选器选取发送，在 A、B 双端核对封面、大小、方向、时长和播放。",
        "系统选择器识别为 4.37 MB MP4；双端均显示 4.2 MB 视频封面和 19:37 时间。A 端播放器识别横屏画面与 00:52 时长，可正常播放、暂停和拖动。",
        checked(
            repo,
            fixture,
            album_b / "003-video-filter-search.png",
            album_b / "003-video-filter-search.xml",
            album_b / "004-video-sender-settled.png",
            album_b / "004-video-sender-settled.xml",
            album_a / "001-video-receiver.png",
            album_a / "001-video-receiver.xml",
            playback / "001-video-opened.png",
            playback / "002-video-paused.png",
            playback / "003-video-seeked.png",
        ),
    )
    set_case(
        cases,
        "IM-182",
        "FAIL",
        "B 端从摄像头入口选择录像，使用内置录像页真实录制并点击完成；持续观察上传进度、失败恢复和 A 端到达情况。",
        "录像可启动并计时，但点击完成后没有预览确认，直接返回聊天上传；进度到 61% 后变为 Retry send，联网状态精确重试仍失败，A 端未收到现场视频。",
        checked(
            repo,
            camera_b / "001-camera-mode-sheet.png",
            camera_b / "002-video-recorder-ready.png",
            camera_b / "003-video-recording-5s.png",
            camera_b / "003-video-recording-5s.xml",
            camera_b / "005-video-recorded-preview.png",
            camera_b / "005-video-recorded-preview.xml",
            camera_b / "006-camera-video-sender-settled.png",
            camera_b / "006-camera-video-sender-settled.xml",
            camera_b / "007-camera-video-retry-result.png",
            camera_b / "007-camera-video-retry-result.xml",
            camera_a / "001-camera-video-receiver.png",
            camera_a / "002-after-camera-video-retry.png",
            repo / "lib/features/chat/pages/chat_video_recorder_page.dart",
            repo / "lib/features/chat/providers/message_provider.dart",
        ),
        "P1",
    )
    set_case(
        cases,
        "IM-186",
        "FAIL",
        "A 端打开收到的视频，依次执行自动播放、暂停、拖动到新进度、强制横屏、恢复竖屏并退出。",
        "播放、暂停、拖动和退出均正常；但强制横屏后画面仍保持竖屏，横屏前后截图 SHA-256 完全一致。启动代码只允许 portraitUp/portraitDown，播放器没有临时放开方向。",
        checked(
            repo,
            playback / "001-video-opened.png",
            playback / "002-video-paused.png",
            playback / "003-video-seeked.png",
            playback / "004-video-landscape.png",
            playback / "005-video-exit-to-chat.png",
            repo / "lib/bootstrap/bootstrap_native.dart",
            repo / "lib/features/chat/widgets/message_bubble_video_player.dart",
        ),
        "P2",
    )

    write_report(repo, run_dir, cases, environment, log_summary)
    summary = {
        status: sum(case.status == status for case in cases.values())
        for status in ("PASS", "FAIL", "SKIP", "BLOCKED")
    }
    print(json.dumps({"summary": summary}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
