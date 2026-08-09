#!/usr/bin/env python3
"""Apply visually reviewed IM-400 media conclusions to the active report."""

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


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", required=True)
    parser.add_argument("--run-dir", required=True)
    args = parser.parse_args()

    repo = Path(args.repo).resolve()
    run_dir = Path(args.run_dir).resolve()
    media = run_dir / "media-picker-probe"
    cases, environment, log_summary = load_report(run_dir)

    gif_source = repo / "uploads/stickers/duck/duck_01.gif"
    gif_preview_frames = [
        media / "device-a-gif" / f"{index:03d}-gif-preview-frame.png"
        for index in range(10, 14)
    ]
    frame_hashes = [sha256(path) for path in gif_preview_frames]
    analysis = {
        "source": rel(gif_source, repo),
        "source_bytes": gif_source.stat().st_size,
        "source_sha256": sha256(gif_source),
        "source_frame_count": 24,
        "source_frame_duration_ms": 80,
        "preview_frame_files": [rel(path, repo) for path in gif_preview_frames],
        "preview_frame_sha256": frame_hashes,
        "all_preview_frames_identical": len(set(frame_hashes)) == 1,
    }
    gif_analysis = media / "gif-frame-analysis.json"
    gif_analysis.write_text(
        json.dumps(analysis, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    if not analysis["all_preview_frames_identical"]:
        raise RuntimeError("GIF 预览帧不再相同，不能沿用静态播放结论")

    fixtures = run_dir / "media-fixtures.json"

    set_case(
        cases,
        "IM-141",
        "PASS",
        "B 端从系统相册选择唯一 PNG，核对发送端气泡、A 端实时到达和接收端全屏预览。",
        "发送端显示正确图片气泡和已读双勾；A 端收到同一图片，点击后进入应用内全屏预览，内容与受控素材一致。",
        checked(
            repo,
            fixtures,
            media / "picker-search-png.png",
            media / "png-sender-after-2.png",
            media / "device-a" / "002-png-receiver-arrival.png",
            media / "device-a" / "003-png-receiver-preview.png",
        ),
    )
    set_case(
        cases,
        "IM-142",
        "PASS",
        "在系统文件选择器长按进入多选，选中两张不同 PNG 后一次发送，并在双端核对相册气泡。",
        "选择器明确显示“已选择 2 项”；发送端和接收端均显示由两张不同图片组成的 17:57 相册气泡，两端内容一致。",
        checked(
            repo,
            media / "device-b-multiselect-png" / "003-two-png-selected.png",
            media / "device-b-multiselect-png" / "004-two-png-sender-settled.png",
            media / "device-b-multiselect-png" / "004-two-png-sender-settled.xml",
            media / "device-a-multiselect-png" / "002-two-png-receiver.png",
            media / "device-a-multiselect-png" / "002-two-png-receiver.xml",
        ),
    )
    set_case(
        cases,
        "IM-144",
        "FAIL",
        "打开聊天附件相册入口并核对系统选择器与客户端发送实现中的原图开关和参数。",
        "界面没有“原图”开关；聊天相册调用固定使用 imageQuality=80、maxWidth/maxHeight=1920，无法按用户选择发送原始文件。",
        checked(
            repo,
            media / "002-attachment-menu.png",
            media / "003-gallery-open.png",
            repo / "lib/features/chat/pages/chat_detail_media_image_actions.dart",
        ),
        "P2",
    )
    set_case(
        cases,
        "IM-147",
        "FAIL",
        "发送 24 帧、每帧 80ms 的受控 GIF，双端核对气泡并在接收端全屏预览连续取四帧。",
        "GIF 可发送和打开，但气泡与全屏预览只显示静态首帧；间隔取证的四张预览截图哈希完全一致，未播放动画。",
        checked(
            repo,
            fixtures,
            gif_analysis,
            media / "device-b-gif" / "005-gif-sender-arrival-a.png",
            media / "device-a-gif" / "002-gif-receiver-frame.png",
            *gif_preview_frames,
        ),
        "P2",
    )
    set_case(
        cases,
        "IM-148",
        "PASS",
        "发送 alpha 范围 0-255 的透明 PNG，并在发送端、接收端和黑色全屏预览背景下核对透明区域。",
        "透明 PNG 双端到达；边角区域没有被填成白底，全屏黑色背景可透过透明像素，主体边缘保持正确。",
        checked(
            repo,
            fixtures,
            media / "device-b-transparent" / "005-transparent-sender.png",
            media / "device-a-transparent" / "002-transparent-receiver.png",
            media / "device-a-transparent" / "003-transparent-preview.png",
        ),
    )
    set_case(
        cases,
        "IM-153",
        "PASS",
        "B 端从聊天摄像头入口调用华为系统相机，实际拍照并确认，随后在 A、B 两端核对。",
        "系统相机正常启动并返回照片；B 端发送成功并显示已读双勾，A 端收到相同的 18:08 照片。",
        checked(
            repo,
            media / "device-b-camera-send" / "002-camera-ready.png",
            media / "device-b-camera-send" / "003-after-shutter.png",
            media / "device-b-camera-send" / "004-camera-photo-sender.png",
            media / "device-a-camera-send" / "002-camera-photo-receiver.png",
        ),
    )
    set_case(
        cases,
        "IM-154",
        "PASS",
        "授权相机后从聊天进入系统相机，不拍照直接返回，并核对聊天消息列表。",
        "系统相机正常打开；返回后回到原会话，未生成新图片消息，也未出现崩溃或残留遮罩。",
        checked(
            repo,
            media / "device-b-camera" / "002-camera-launched-granted.png",
            media / "device-b-camera" / "003-camera-cancel-return.png",
        ),
    )
    set_case(
        cases,
        "IM-155",
        "PASS",
        "在 CAMERA 未授权状态进入拍照流程，在系统权限弹窗点击“禁止”。",
        "应用返回聊天页并明确显示“拍摄失败，请重试”，未发送空消息、未卡死且进程保持运行。",
        checked(
            repo,
            media / "device-b-camera" / "003-after-photo-launch.png",
            media / "device-b-camera" / "003-after-photo-launch.xml",
            media / "device-b-camera" / "004-camera-denied-result.png",
        ),
    )
    set_case(
        cases,
        "IM-158",
        "PASS",
        "从两图相册气泡打开第 1 张，先记录适配视图，再执行双指放大和单指平移。",
        "预览显示 1/2；双指后图片明显放大到局部像素级，随后平移到另一内容区域，手势生效且预览未退出。",
        checked(
            repo,
            media / "device-a-gesture" / "004-collage-item-preview-fit.png",
            media / "device-a-gesture" / "005-collage-item-preview-zoom.png",
            media / "device-a-gesture" / "006-collage-item-preview-pan.png",
        ),
    )
    set_case(
        cases,
        "IM-159",
        "PASS",
        "A 端打开收到的实拍图片，点击右上角保存按钮，并核对应用反馈与系统媒体库。",
        "应用提示“已保存到相册”；系统媒体库新增 Pictures/GenericIM_1784110258444.jpg（media_id=1950）。",
        checked(
            repo,
            fixtures,
            media / "device-a-save" / "001-preview-before-save.png",
            media / "device-a-save" / "002-after-save-tap.png",
        ),
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
