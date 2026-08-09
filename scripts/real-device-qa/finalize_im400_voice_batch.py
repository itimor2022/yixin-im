#!/usr/bin/env python3
"""Apply visually reviewed IM-400 voice conclusions to the active report."""

from __future__ import annotations

import argparse
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


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", required=True)
    parser.add_argument("--run-dir", required=True)
    args = parser.parse_args()

    repo = Path(args.repo).resolve()
    run_dir = Path(args.run_dir).resolve()
    voice = run_dir / "voice-batch"
    cases, environment, log_summary = load_report(run_dir)

    permission = voice / "device-b-permission"
    record = voice / "device-b-record"
    short = voice / "device-b-short"
    normal_b = voice / "device-b-normal"
    normal_a = voice / "device-a-normal"
    cancel = voice / "device-b-cancel"
    voip = voice / "device-b-voip-interrupt"
    notification = voice / "device-b-notification-interrupt"
    background = voice / "device-b-background"
    offline = voice / "device-b-offline"
    continuous = voice / "device-a-continuous"
    switch = voice / "device-a-switch"
    transcript = voice / "device-a-transcript"

    require_text(permission / "003-microphone-denied-result.xml", "需要麦克风权限才能录音")
    require_text(record / "001-recording-active.xml", "滑动取消", "00:02")
    require_text(short / "003-short-after-send.xml", "输入消息")
    require_text(record / "005-return-app-after-background.xml", "滑动取消", "00:00")
    require_text(normal_b / "002-normal-voice-sender.xml", "0:04", "18:50")
    require_text(normal_a / "002-normal-voice-receiver.xml", "0:04", "18:50")
    require_text(voip / "003-return-recording-continued.xml", "滑动取消", "00:53")
    require_text(notification / "001-recording-before-notification.xml", "滑动取消", "00:05")
    require_text(notification / "002-recording-after-notification.xml", "滑动取消", "00:13")
    require_text(notification / "003-audio-focus-logcat.txt", "requestAudioFocus", "USAGE_NOTIFICATION")
    require_text(background / "003-return-recording-continued.xml", "滑动取消", "00:06")
    require_text(offline / "003-offline-send-result.xml", "Retry send", "0:05", "19:21")
    require_text(offline / "010-uiautomator-retry-result.xml", "Retry send", "0:05", "19:21")
    require_text(switch / "004-second-playing-first-stopped.xml", "0:04", "0:00", "19:11")
    require_text(transcript / "002-transcript-result.xml", "语音转文字服务未配置")

    set_case(
        cases,
        "IM-161",
        "PASS",
        "B 端点击聊天栏麦克风，在已授权状态启动真实录音并观察录音覆盖层、计时和波形。",
        "录音成功启动；界面显示“← 滑动取消”、00:02 计时、动态波形和发送按钮，没有假录音或崩溃。",
        checked(repo, record / "001-recording-active.png", record / "001-recording-active.xml"),
    )
    set_case(
        cases,
        "IM-162",
        "FAIL",
        "启动录音后约 250ms 立即点击发送，核对是否拒绝过短语音并给出明确提示。",
        "过短语音没有发送，但界面静默返回输入栏，没有任何“录音太短”提示；服务仅返回 null，用户无法理解失败原因。",
        checked(
            repo,
            short / "001-before-short.png",
            short / "002-short-active.png",
            short / "003-short-after-send.png",
            short / "003-short-after-send.xml",
            repo / "lib/core/services/voice_record_service.dart",
        ),
        "P2",
    )
    set_case(
        cases,
        "IM-163",
        "FAIL",
        "持续录音超过 300 秒上限后返回应用，核对是否自动结束、发送或给出一致的上限状态。",
        "超过上限后未自动发送；返回应用仍残留录音覆盖层且计时回到 00:00。服务在 300 秒只内部 stop，页面录音状态未同步，形成僵尸覆盖层。",
        checked(
            repo,
            record / "005-return-app-after-background.png",
            record / "005-return-app-after-background.xml",
            record / "007-stale-overlay-dismissed.png",
            repo / "lib/core/services/voice_record_service.dart",
            repo / "lib/features/chat/pages/chat_detail_media_voice_actions.dart",
        ),
        "P2",
    )
    set_case(
        cases,
        "IM-164",
        "PASS",
        "B 端录制约 3 秒语音并发送，随后在 A、B 双端核对消息、时长、到达和播放能力。",
        "B 端生成 0:04 语音并显示已读双勾；A 端实时收到相同 0:04 语音，点击后可完整播放并复位。",
        checked(
            repo,
            normal_b / "001-normal-recording-3s.png",
            normal_b / "002-normal-voice-sender.png",
            normal_b / "002-normal-voice-sender.xml",
            normal_a / "002-normal-voice-receiver.png",
            normal_a / "003-normal-voice-playing.png",
            normal_a / "004-normal-voice-completed.png",
        ),
    )
    set_case(
        cases,
        "IM-165",
        "PASS",
        "按当前产品覆盖层明确展示的“← 滑动取消”手势，录音中向左滑动超过阈值并核对消息列表。",
        "横向取消手势生效，录音覆盖层关闭且没有生成或误发新语音；产品采用左滑而非传统上滑交互。",
        checked(
            repo,
            cancel / "001-cancel-recording.png",
            cancel / "001-cancel-recording.xml",
            cancel / "002-left-cancelled.png",
            cancel / "002-left-cancelled.xml",
        ),
    )
    set_case(
        cases,
        "IM-166",
        "PASS",
        "取消一段录音后立即再次启动录音，核对覆盖层、计时是否从新会话复位，再次取消清理。",
        "第二次录音正常启动并从 00:01 重新计时，波形和取消手势可用；再次取消后无残留覆盖层或误发消息。",
        checked(
            repo,
            cancel / "002-left-cancelled.png",
            cancel / "003-rerecord-reset.png",
            cancel / "003-rerecord-reset.xml",
            cancel / "004-rerecord-cancelled.png",
            cancel / "004-rerecord-cancelled.xml",
        ),
    )
    set_case(
        cases,
        "IM-167",
        "FAIL",
        "B 端录音期间由 A 端发起真实应用内语音通话，观察 B 端来电页；通话结束后返回聊天核对录音状态和是否误发。",
        "B 端正确进入语音来电页，但录音没有安全结束；返回聊天后隐藏录音继续到 00:53，必须人工左滑取消，存在隐私和损坏录音风险。",
        checked(
            repo,
            record / "001-recording-active.png",
            voip / "001-device-a-calling.png",
            voip / "002-device-b-incoming-interrupt.png",
            voip / "003-return-recording-continued.png",
            voip / "003-return-recording-continued.xml",
            voip / "004-residual-recording-cancelled.png",
        ),
        "P1",
    )
    set_case(
        cases,
        "IM-168",
        "PASS",
        "B 端录音时由系统 shell 通知通道播放真实通知音，日志核对 USAGE_NOTIFICATION 瞬时音频焦点请求，再比对录音前后状态。",
        "系统通知声成功请求并释放瞬时音频焦点；录音覆盖层保持可见且计时从 00:05 连续到 00:13，界面与实际录音状态一致，随后可正常取消。",
        checked(
            repo,
            notification / "001-recording-before-notification.png",
            notification / "001-recording-before-notification.xml",
            notification / "002-recording-after-notification.png",
            notification / "002-recording-after-notification.xml",
            notification / "003-audio-focus-logcat.txt",
        ),
    )
    set_case(
        cases,
        "IM-169",
        "FAIL",
        "录音中按 Home 返回桌面，停留约 2 秒后重新打开应用，核对录音是否按规则暂停或取消。",
        "录音在后台隐藏继续；返回聊天时覆盖层计时已到 00:06，没有暂停、取消或后台录音提示，必须人工取消。",
        checked(
            repo,
            background / "001-recording-before-home.png",
            background / "002-home-while-recording.png",
            background / "003-return-recording-continued.png",
            background / "003-return-recording-continued.xml",
            background / "004-background-record-cancelled.png",
        ),
        "P1",
    )
    set_case(
        cases,
        "IM-170",
        "PASS",
        "撤销 B 端 RECORD_AUDIO 权限，从聊天栏启动录音并在系统权限框选择禁止。",
        "系统权限框正常出现；拒绝后应用明确提示“需要麦克风权限才能录音”，未显示假录音动画、未生成空消息且进程稳定。",
        checked(
            repo,
            permission / "002-microphone-permission.png",
            permission / "002-microphone-permission.xml",
            permission / "003-microphone-denied-result.png",
            permission / "003-microphone-denied-result.xml",
        ),
    )
    set_case(
        cases,
        "IM-171",
        "FAIL",
        "B 端录音完成前关闭 Wi-Fi，发送后核对本地保留；恢复已验证网络后分别执行坐标点击和无障碍精确点击“Retry send”，再核对 A 端。",
        "离线语音以 0:05 失败气泡保留并提供重试按钮；但联网后多次精确重试仍保持失败，A 端未收到。源码仅允许 mediaUrl 以 /uploads 开头的语音重试，首次上传失败保存的是本地路径。",
        checked(
            repo,
            offline / "002-recording-offline.png",
            offline / "003-offline-send-result.png",
            offline / "003-offline-send-result.xml",
            offline / "004-online-recovery.png",
            offline / "010-uiautomator-retry-result.png",
            offline / "010-uiautomator-retry-result.xml",
            offline / "011-device-a-after-retry.png",
            offline / "011-device-a-after-retry.xml",
            repo / "lib/features/chat/providers/message_provider.dart",
        ),
        "P1",
    )
    set_case(
        cases,
        "IM-172",
        "PASS",
        "A 端点击收到的 0:04 语音，核对播放态、进度变化和完成后的复位状态。",
        "语音可完整播放；播放时按钮变为暂停且进度推进，完成后恢复播放图标并回到起点，没有卡死或重复播放。",
        checked(
            repo,
            normal_a / "002-normal-voice-receiver.png",
            normal_a / "003-normal-voice-playing.png",
            normal_a / "004-normal-voice-completed.png",
            normal_a / "004-normal-voice-completed.xml",
        ),
    )
    set_case(
        cases,
        "IM-173",
        "FAIL",
        "A 端存在相邻的 0:04 和 0:03 两条语音；点击第一条并持续观察到其播放完成后，再核对第二条是否按序自动播放。",
        "第一条完成后第二条仍保持未播放，9 秒后两条均为停止态；源码完成回调只复位当前气泡，没有语音队列或下一条触发逻辑。",
        checked(
            repo,
            switch / "002-two-voices-received.png",
            continuous / "001-after-first-completed.png",
            continuous / "003-after-9s.png",
            continuous / "003-after-9s.xml",
            continuous / "002-playback-logcat.txt",
            repo / "lib/features/chat/widgets/message_bubble_voice.dart",
        ),
        "P2",
    )
    set_case(
        cases,
        "IM-174",
        "PASS",
        "A 端播放第一条语音时点击第二条，连续截取两条气泡的图标和进度状态。",
        "点击第二条后第一条立即恢复播放图标并停止，第二条从 0:00 进入暂停图标播放态；没有两条声音并行。",
        checked(
            repo,
            switch / "002-two-voices-received.png",
            switch / "003-first-playing.png",
            switch / "003-first-playing.xml",
            switch / "004-second-playing-first-stopped.png",
            switch / "004-second-playing-first-stopped.xml",
        ),
    )
    set_case(
        cases,
        "IM-175",
        "FAIL",
        "在真机语音气泡播放界面核对所有可操作控件，并审查播放音频上下文的路由配置。",
        "语音气泡只有播放和转文字控件，没有听筒/扬声器切换入口或状态图标；音频上下文固定 isSpeakerphoneOn=true，无法手动切换。",
        checked(
            repo,
            normal_a / "002-normal-voice-receiver.png",
            switch / "004-second-playing-first-stopped.png",
            repo / "lib/core/services/voice_playback_audio_context.dart",
            repo / "lib/features/chat/widgets/message_bubble_voice.dart",
        ),
        "P2",
    )
    set_case(
        cases,
        "IM-176",
        "FAIL",
        "核对真机语音播放界面和播放实现中的距离传感器、屏幕熄灭与听筒路由处理。",
        "界面没有距离感应播放状态；播放实现固定扬声器并未注册 proximity 传感器，也没有靠近熄屏/转听筒及移开恢复逻辑。",
        checked(
            repo,
            normal_a / "003-normal-voice-playing.png",
            repo / "lib/core/services/voice_playback_audio_context.dart",
            repo / "lib/features/chat/widgets/message_bubble_voice.dart",
        ),
        "P2",
    )
    set_case(
        cases,
        "IM-179",
        "FAIL",
        "A 端点击已接收语音的“转文字”，观察加载态并等待服务返回结果。",
        "转写入口和加载态可用，但最终只显示“语音转文字服务未配置”，没有转写结果、语言识别或可执行重试，生产依赖未就绪。",
        checked(
            repo,
            transcript / "001-transcribing.png",
            transcript / "001-transcribing.xml",
            transcript / "002-transcript-result.png",
            transcript / "002-transcript-result.xml",
            repo / "lib/features/chat/widgets/message_bubble_voice.dart",
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
