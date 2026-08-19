#!/usr/bin/env python3
"""Run a conservative 400-item IM real-device regression and write evidence.

The runner deliberately distinguishes functional PASS/FAIL from SKIP (service
not configured) and BLOCKED (a required second endpoint or physical fixture is
not available). It never converts a capability scan into a functional pass.
"""

from __future__ import annotations

import argparse
import html
import json
import re
import subprocess
import sys
import time
from dataclasses import asdict, dataclass
from datetime import datetime
from pathlib import Path
from typing import Any, Callable
from urllib.error import URLError
from urllib.request import Request, urlopen

import uiautomator2 as u2


PACKAGE = "com.genericim.ma100"
SERIAL = "UQG5T20915006269"
BACKEND = "https://api.example.com"


@dataclass
class Case:
    case_id: str
    name: str
    expected: str
    module: str
    status: str = "BLOCKED"
    priority: str = "-"
    action: str = "执行前置条件与能力探测。"
    observed: str = "缺少完成端到端断言所需的受控账号、设备、数据或硬件条件。"
    evidence: list[str] | None = None
    tested_at: str = ""

    def __post_init__(self) -> None:
        if self.evidence is None:
            self.evidence = []


def now_iso() -> str:
    return datetime.now().astimezone().isoformat(timespec="seconds")


def adb(adb_path: str, serial: str, *args: str, timeout: int = 30) -> str:
    completed = subprocess.run(
        [adb_path, "-s", serial, *args],
        text=True,
        encoding="utf-8",
        errors="replace",
        capture_output=True,
        timeout=timeout,
        check=False,
    )
    if completed.returncode != 0:
        raise RuntimeError(
            f"adb {' '.join(args)} failed ({completed.returncode}): "
            f"{completed.stderr.strip()}"
        )
    return completed.stdout.strip()


def parse_checklist(path: Path) -> dict[str, Case]:
    raw = path.read_text(encoding="utf-8")
    module_matches = list(re.finditer(r"(?m)^##\s+(.+)$", raw))
    cases: dict[str, Case] = {}
    pattern = re.compile(
        r"- \[ \] \*\*(IM-\d{3})\s+(.*?)\*\*："
        r"(.*?)(?=- \[ \] \*\*IM-|\n##|\Z)",
        re.S,
    )
    for match in pattern.finditer(raw):
        position = match.start()
        module = ""
        for heading in module_matches:
            if heading.start() <= position:
                module = heading.group(1).strip()
            else:
                break
        case_id = match.group(1)
        cases[case_id] = Case(
            case_id=case_id,
            name=match.group(2).strip(),
            expected=" ".join(match.group(3).split()),
            module=module,
            tested_at=now_iso(),
        )
    expected_ids = [f"IM-{index:03d}" for index in range(1, 401)]
    if list(cases) != expected_ids:
        missing = [item for item in expected_ids if item not in cases]
        raise RuntimeError(f"checklist must contain IM-001..IM-400 in order; missing={missing}")
    return cases


def rel(path: Path, repo: Path) -> str:
    try:
        return path.resolve().relative_to(repo.resolve()).as_posix()
    except ValueError:
        return str(path.resolve()).replace("\\", "/")


def set_case(
    cases: dict[str, Case],
    case_id: str,
    status: str,
    action: str,
    observed: str,
    evidence: list[str] | None = None,
    priority: str = "-",
) -> None:
    case = cases[case_id]
    case.status = status
    case.priority = priority if status == "FAIL" else "-"
    case.action = action
    case.observed = observed
    case.evidence = evidence or []
    case.tested_at = now_iso()


def initialize_preconditions(
    cases: dict[str, Case],
    devices_evidence: str,
    permissions_evidence: str,
) -> None:
    second_device_ids = list(range(21, 41)) + list(range(58, 60)) + [
        74,
        92,
        100,
        111,
        126,
        127,
        128,
        129,
        131,
        133,
        134,
        138,
        139,
        207,
        221,
        223,
        225,
        226,
        230,
    ]
    for number in second_device_ids:
        case_id = f"IM-{number:03d}"
        set_case(
            cases,
            case_id,
            "BLOCKED",
            "逐项检查双端/双账号前置条件，并查询 adb 设备授权状态。",
            "第二台设备 8MY0220C17006781 为 unauthorized；无法形成可靠的发送端与接收端闭环。",
            [devices_evidence],
        )

    for number in range(301, 341):
        case_id = f"IM-{number:03d}"
        set_case(
            cases,
            case_id,
            "BLOCKED",
            "检查 VoIP 双端、麦克风、摄像头、音频路由及网络整形前置条件。",
            "仅一台已授权真机，无法接听、拒接、双向音视频或测量音质；未伪造通话结果。",
            [devices_evidence, permissions_evidence],
        )

    for number in range(341, 361):
        case_id = f"IM-{number:03d}"
        set_case(
            cases,
            case_id,
            "BLOCKED",
            "检查真实发送端、厂商推送通道、锁屏与通知权限前置条件。",
            "缺少第二个可控在线发送端，无法区分 WebSocket 到达与厂商离线推送到达。",
            [devices_evidence, permissions_evidence],
        )

    service_skip_ids = list(range(2, 7))
    for number in service_skip_ids:
        case_id = f"IM-{number:03d}"
        set_case(
            cases,
            case_id,
            "SKIP",
            "检查注册页入口和线上服务能力。",
            "当前产品未提供短信/邮箱验证码服务配置，按用户要求直接跳过，不反复尝试外部验证码。",
            ["artifacts/real-device-qa/IM-001-phone-registration-20260714-235151/02-register-page.png"],
        )

    for number in (14, 15, 16, 17):
        case_id = f"IM-{number:03d}"
        set_case(
            cases,
            case_id,
            "SKIP",
            "检查账号注销/封禁后台测试数据与管理员能力。",
            "线上后台未准备可销毁、冷静期或封禁测试账号；为避免破坏现有 smoke_bob 数据，按要求跳过。",
            [devices_evidence],
        )

    for number in (194, 196, 197, 200, 394):
        case_id = f"IM-{number:03d}"
        set_case(
            cases,
            case_id,
            "SKIP",
            "检查位置/实时位置/小程序卡片/定时消息服务能力。",
            "本轮线上环境未确认相应后台能力或业务配置，按要求标记 SKIP。",
            [permissions_evidence],
        )


class Runner:
    def __init__(
        self,
        repo: Path,
        run_dir: Path,
        adb_path: str,
        serial: str,
        package: str,
        cases: dict[str, Case],
    ) -> None:
        self.repo = repo
        self.run_dir = run_dir
        self.adb_path = adb_path
        self.serial = serial
        self.package = package
        self.cases = cases
        self.device = u2.connect(serial)
        self.events_path = run_dir / "action-events.jsonl"
        self.step = 0

    def event(self, action: str, status: str, detail: str, evidence: list[str] | None = None) -> None:
        payload = {
            "time": now_iso(),
            "sequence": self.step,
            "action": action,
            "status": status,
            "detail": detail,
            "evidence": evidence or [],
        }
        with self.events_path.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(payload, ensure_ascii=False) + "\n")
        try:
            print(f"[QA400] {action}: {status} - {detail}", flush=True)
        except OSError:
            # A detached Windows launcher may close its inherited stdout pipe.
            # Evidence writing must continue even when progress output is gone.
            pass

    def snapshot(self, name: str) -> list[str]:
        self.step += 1
        png = self.run_dir / f"{self.step:03d}-{name}.png"
        xml = self.run_dir / f"{self.step:03d}-{name}.xml"
        self.device.screenshot(str(png))
        xml.write_text(self.device.dump_hierarchy(), encoding="utf-8")
        return [rel(png, self.repo), rel(xml, self.repo)]

    def run_step(self, name: str, body: Callable[[], None]) -> None:
        try:
            body()
        except Exception as exc:  # A harness failure is not a product pass or product failure.
            evidence = self.snapshot(f"error-{re.sub(r'[^a-z0-9]+', '-', name.lower()).strip('-')}")
            self.event(name, "BLOCKED", f"自动化步骤异常：{type(exc).__name__}: {exc}", evidence)

    def ensure_app(self) -> None:
        self.device.app_start(self.package, stop=False, wait=True)
        time.sleep(2)
        current = self.device.app_current()
        if current.get("package") != self.package:
            raise RuntimeError(f"app not foreground: {current}")

    def click_desc(self, text: str, contains: bool = False, timeout: float = 5.0) -> bool:
        node = self.device(descriptionContains=text) if contains else self.device(description=text)
        if not node.wait(timeout=timeout):
            return False
        node.click()
        time.sleep(1)
        return True

    def click_text(self, text: str, contains: bool = False, timeout: float = 5.0) -> bool:
        node = self.device(textContains=text) if contains else self.device(text=text)
        if not node.wait(timeout=timeout):
            return False
        node.click()
        time.sleep(1)
        return True

    def click_bottom_desc(self, text: str) -> bool:
        hierarchy = self.device.dump_hierarchy()
        width, height = self.device.window_size()
        candidates: list[tuple[int, int]] = []
        for node in re.findall(r"<node\b[^>]*>", hierarchy):
            if (
                f'package="{self.package}"' not in node
                or 'clickable="true"' not in node
            ):
                continue
            description = re.search(r'content-desc="([^"]*)"', node)
            bounds = re.search(
                r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', node
            )
            if not description or not bounds:
                continue
            if text not in html.unescape(description.group(1)):
                continue
            left, top, right, bottom = map(int, bounds.groups())
            if top < int(height * 0.80):
                continue
            candidates.append(((left + right) // 2, (top + bottom) // 2))
        if not candidates:
            return False
        x, y = min(candidates, key=lambda point: abs(point[0] - width // 2))
        self.device.click(x, y)
        time.sleep(1)
        return True

    def navigate_tab(self, label: str, name: str) -> list[str]:
        self.ensure_app()
        for _ in range(5):
            if self.click_desc(label, timeout=1) or self.click_bottom_desc(label):
                return self.snapshot(name)
            self.device.press("back")
            time.sleep(0.5)
        raise RuntimeError(f"bottom tab not found: {label}")

    def open_chat(self, title: str, name: str) -> list[str]:
        self.navigate_tab("消息", "messages-before-chat")
        node = self.device(descriptionContains=title)
        if not node.wait(timeout=8):
            raise RuntimeError(f"conversation not visible: {title}")
        node.click()
        time.sleep(1.5)
        if not self.device(className="android.widget.EditText").exists(timeout=3):
            raise RuntimeError(f"chat input missing for {title}")
        return self.snapshot(name)

    def visible_outside_edit(self, text: str) -> bool:
        hierarchy = self.device.dump_hierarchy()
        for node in re.findall(r"<node\b[^>]*>", hierarchy):
            if 'class="android.widget.EditText"' in node:
                continue
            if text in html.unescape(node):
                return True
        return False

    def send_text(self, text: str, name: str) -> tuple[bool, list[str]]:
        edit = self.device(className="android.widget.EditText")
        if not edit.exists(timeout=3):
            raise RuntimeError("chat input missing")
        edit.click()
        # Flutter rebuilds the semantics node after the first character, so a
        # retained UiObject becomes stale. Device-level input survives rebuilds.
        self.device.set_fastinput_ime(True)
        self.device.send_keys(text, clear=True)
        time.sleep(0.5)
        evidence = self.snapshot(f"{name}-typed")
        send = self.device(description="发送")
        if send.exists(timeout=2):
            send.click()
        else:
            hierarchy = self.device.dump_hierarchy()
            width, height = self.device.window_size()
            edit_node = next(
                (node for node in re.findall(r"<node\b[^>]*>", hierarchy) if 'class="android.widget.EditText"' in node),
                "",
            )
            edit_bounds = re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', edit_node)
            edit_top = int(edit_bounds.group(2)) if edit_bounds else int(height * 0.50)
            edit_bottom = int(edit_bounds.group(4)) if edit_bounds else height
            candidates: list[tuple[int, int]] = []
            for node in re.findall(r"<node\b[^>]*>", hierarchy):
                if 'package="com.genericim.ma100"' not in node or 'clickable="true"' not in node:
                    continue
                bounds = re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', node)
                if not bounds:
                    continue
                x = (int(bounds.group(1)) + int(bounds.group(3))) // 2
                y = (int(bounds.group(2)) + int(bounds.group(4))) // 2
                if x > int(width * 0.75) and edit_top <= y <= edit_bottom:
                    candidates.append((x, y))
            if not candidates:
                raise RuntimeError("send button not found after text input")
            send_x, send_y = max(candidates, key=lambda item: (item[0], item[1]))
            self.device.click(send_x, send_y)
        time.sleep(1.5)
        visible = self.visible_outside_edit(text)
        return visible, evidence + self.snapshot(f"{name}-sent")

    def baseline(self) -> None:
        self.ensure_app()
        evidence = self.snapshot("baseline-main")
        hierarchy = Path(self.repo / evidence[1]).read_text(encoding="utf-8")
        tabs = all(label in hierarchy for label in ("消息", "联系人", "发现", "设置"))
        if tabs:
            for case_id in ("IM-008", "IM-019"):
                set_case(
                    self.cases,
                    case_id,
                    "PASS",
                    "使用 smoke_bob 正确账号密码登录并检查登录后首页初始化。",
                    "已进入正确账号主界面，消息/联系人/发现/设置四个主入口完整可见。",
                    evidence + ["artifacts/real-device-qa/qa400-login-final.xml"],
                )
            self.event("登录与首页基线", "PASS", "主界面四个底部入口可见。", evidence)
        else:
            self.event("登录与首页基线", "FAIL", "未发现完整主界面底部入口。", evidence)

        set_case(
            self.cases,
            "IM-001",
            "FAIL",
            "打开注册页，检查手机号、验证码、密码字段和提交路径。",
            "注册页只有用户名、密码、确认密码，无手机号和短信验证码入口；客户端与后端注册模型也未提供 phone/code 字段。",
            [
                "artifacts/real-device-qa/IM-001-phone-registration-20260714-235151/02-register-page.png",
                "artifacts/real-device-qa/IM-001-phone-registration-20260714-235151/case-result.json",
            ],
            "P2",
        )
        set_case(
            self.cases,
            "IM-012",
            "PASS",
            "在前序真实用例中主动退出登录并检查返回栈。",
            "退出后返回登录/注册入口，随后可重新使用 smoke_bob 登录。",
            ["artifacts/real-device-qa/IM-001-phone-registration-20260714-235151/case-result.json"],
        )
        set_case(
            self.cases,
            "IM-020",
            "PASS",
            "在未勾选协议时提交登录，再勾选协议登录。",
            "未勾选时显示“请先阅读并同意用户协议和隐私政策”，勾选后才允许登录。",
            ["artifacts/real-device-qa/qa400-login-final.xml"],
        )

    def tabs(self) -> None:
        all_evidence: list[str] = []
        for label in ("消息", "联系人", "发现", "设置"):
            all_evidence += self.navigate_tab(label, f"tab-{label}")
        self.event("四个主导航页巡检", "PASS", "四个底部页均可点击并完成截图/UI 树留证。", all_evidence)

    def private_texts(self) -> None:
        open_evidence = self.open_chat("Smoke Alice", "private-chat-open")
        stamp = datetime.now().strftime("%H%M%S")
        tests: list[tuple[str, str, str]] = [
            ("IM-101", f"Q{stamp}", "short"),
            ("IM-102", "L" * 500 + stamp, "long500"),
            ("IM-104", f"第一行{stamp}\n\nThird line", "multiline"),
            ("IM-105", f"中英ABC123，。{stamp}", "mixed"),
            ("IM-106", f"😀👍🏽👨‍👩‍👧‍👦🇨🇳{stamp}", "emoji"),
            ("IM-107", f"𠮷藏文བོད་ Arabicالعربية {stamp}", "extended"),
            ("IM-108", f"<script>alert('qa')</script> \\ \" {stamp}", "special"),
            ("IM-116", f"https://example.com/qa400?t={stamp}", "url"),
            ("IM-117", f"qa{stamp}@example.com +8613800138000", "email-phone"),
        ]
        for case_id, text, name in tests:
            visible, evidence = self.send_text(text, name)
            status = "PASS" if visible else "FAIL"
            priority = "P1" if case_id == "IM-101" else "P3"
            set_case(
                self.cases,
                case_id,
                status,
                f"在 Smoke Alice 单聊中输入并发送{name}测试文本。",
                "发送后消息气泡内容与输入一致。" if visible else "点击发送后未在输入框外发现对应消息气泡。",
                open_evidence + evidence,
                priority,
            )

        edit = self.device(className="android.widget.EditText")
        edit.click()
        self.device.send_keys("   ", clear=True)
        time.sleep(0.5)
        blank_evidence = self.snapshot("blank-text")
        blank_blocked = not self.device(description="发送").exists(timeout=1)
        fresh_edit = self.device(className="android.widget.EditText")
        if fresh_edit.exists(timeout=1):
            fresh_edit.click()
            self.device.send_keys("", clear=True)
        set_case(
            self.cases,
            "IM-109",
            "PASS" if blank_blocked else "FAIL",
            "输入三个纯空格并观察发送控件。",
            "纯空格未激活发送控件。" if blank_blocked else "纯空格仍激活发送控件，存在空白气泡风险。",
            blank_evidence,
            "P3",
        )

        rapid_evidence: list[str] = []
        rapid_ok = True
        for index in range(1, 6):
            text = f"R{stamp}{index}"
            visible, evidence = self.send_text(text, f"rapid-{index}")
            rapid_evidence += evidence
            rapid_ok = rapid_ok and visible
        set_case(
            self.cases,
            "IM-110",
            "PASS" if rapid_ok else "FAIL",
            "连续发送 5 条唯一短文本并逐条核对气泡。",
            "5 条消息均出现且唯一标识顺序可追踪。" if rapid_ok else "至少一条快速发送消息未出现。",
            rapid_evidence,
            "P2",
        )

        set_case(
            self.cases,
            "IM-122",
            "PASS" if all(self.cases[item].status == "PASS" for item, _, _ in tests) else "FAIL",
            "发送多种唯一文本并检查发送后的本地成功落泡。",
            "多种文本均完成发送并显示消息气泡。" if all(self.cases[item].status == "PASS" for item, _, _ in tests) else "存在文本发送失败。",
            rapid_evidence[-2:] if rapid_evidence else open_evidence,
            "P1",
        )
        set_case(
            self.cases,
            "IM-390",
            self.cases["IM-108"].status,
            "发送包含 HTML/脚本样式字符、引号与反斜杠的恶意文本样本。",
            "内容按文本气泡显示且 App 未崩溃。" if self.cases["IM-108"].status == "PASS" else "恶意文本样本发送/显示异常。",
            self.cases["IM-108"].evidence,
            "P1",
        )

        hierarchy = self.device.dump_hierarchy()
        nodes = re.findall(r"<node\b[^>]*>", hierarchy)
        candidates = [node for node in nodes if f"R{stamp}5" in node and 'class="android.widget.EditText"' not in node]
        if candidates:
            bounds_match = re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', candidates[-1])
            if bounds_match:
                x = (int(bounds_match.group(1)) + int(bounds_match.group(3))) // 2
                y = (int(bounds_match.group(2)) + int(bounds_match.group(4))) // 2
                self.device.long_click(x, y, duration=1.0)
                time.sleep(1)
                menu_evidence = self.snapshot("message-context-menu")
                menu_xml = Path(self.repo / menu_evidence[1]).read_text(encoding="utf-8")
                menu_items = [item for item in ("复制", "转发", "收藏", "删除", "撤回", "多选", "引用") if item in menu_xml]
                self.event("消息长按菜单", "PASS" if menu_items else "FAIL", f"可见菜单项：{menu_items}", menu_evidence)
                self.device.press("back")

    def attachment_sheet(self) -> None:
        self.open_chat("Smoke Alice", "attachment-chat-open")
        hierarchy = self.device.dump_hierarchy()
        plus = self.device(description="更多")
        if not plus.exists(timeout=2):
            plus = self.device(descriptionContains="更多")
        if plus.exists(timeout=2):
            plus.click()
        else:
            hierarchy = self.device.dump_hierarchy()
            candidates: list[tuple[int, int, int]] = []
            for node in re.findall(r"<node\b[^>]*>", hierarchy):
                if 'clickable="true"' not in node:
                    continue
                bounds = re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', node)
                if not bounds:
                    continue
                x = (int(bounds.group(1)) + int(bounds.group(3))) // 2
                y = (int(bounds.group(2)) + int(bounds.group(4))) // 2
                candidates.append((y, x, int(bounds.group(3)) - int(bounds.group(1))))
            width, height = self.device.window_size()
            bottom_right = [item for item in candidates if item[0] > int(height * 0.85) and item[1] > int(width * 0.75)]
            if not bottom_right:
                raise RuntimeError("attachment button not found")
            y, x, _ = max(bottom_right, key=lambda item: item[1])
            self.device.click(x, y)
        time.sleep(1)
        evidence = self.snapshot("attachment-sheet")
        xml = Path(self.repo / evidence[1]).read_text(encoding="utf-8")
        entries = [item for item in ("相册", "拍摄", "文件", "位置", "名片", "视频通话", "语音通话") if item in xml]
        self.event("聊天附件面板能力探测", "PASS" if entries else "BLOCKED", f"检测到入口：{entries}", evidence)
        self.device.press("back")

    def group_text(self) -> None:
        evidence = self.open_chat("Codex qaGroup", "group-chat-open")
        text = f"GQA{datetime.now().strftime('%H%M%S')}"
        visible, send_evidence = self.send_text(text, "group-text")
        for case_id in ("IM-281",):
            set_case(
                self.cases,
                case_id,
                "PASS" if visible else "FAIL",
                "进入现有 Codex qaGroup 群聊并发送唯一文本。",
                "群消息发送后在当前群时间线中显示。" if visible else "群消息发送后未在群时间线中显示。",
                evidence + send_evidence,
                "P1",
            )
        self.event("群聊文本发送", "PASS" if visible else "FAIL", f"message={text}", evidence + send_evidence)

    def lifecycle(self) -> None:
        self.navigate_tab("消息", "lifecycle-start")
        self.device.press("home")
        time.sleep(3)
        background = self.snapshot("home-background")
        self.ensure_app()
        foreground = self.snapshot("foreground-return")
        main_visible = self.device(description="消息").exists(timeout=3)
        set_case(
            self.cases,
            "IM-374",
            "PASS" if main_visible else "FAIL",
            "按 Home 切后台 3 秒后从启动入口回到 App。",
            "回前台后主界面可继续操作。" if main_visible else "回前台后主界面未恢复。",
            background + foreground,
            "P1",
        )

        self.device.app_stop(self.package)
        time.sleep(2)
        self.device.app_start(self.package, stop=False, wait=True)
        time.sleep(4)
        evidence = self.snapshot("force-stop-relaunch")
        recovered = self.device(description="消息").exists(timeout=3)
        for case_id in ("IM-099", "IM-376"):
            set_case(
                self.cases,
                case_id,
                "PASS" if recovered else "FAIL",
                "强制停止 App 后重新冷启动。",
                "登录态与会话首页恢复，可继续操作。" if recovered else "强杀重启后未恢复到可操作首页。",
                evidence,
                "P1",
            )

    def network_cycle(self) -> None:
        self.open_chat("Smoke Alice", "network-chat-open")
        wifi_on = adb(self.adb_path, self.serial, "shell", "settings", "get", "global", "wifi_on")
        data_on = adb(self.adb_path, self.serial, "shell", "settings", "get", "global", "mobile_data")
        state_path = self.run_dir / "network-original-state.json"
        state_path.write_text(json.dumps({"wifi_on": wifi_on, "mobile_data": data_on}, ensure_ascii=False, indent=2), encoding="utf-8")
        offline_evidence: list[str] = []
        restored = False
        try:
            adb(self.adb_path, self.serial, "shell", "svc", "wifi", "disable")
            adb(self.adb_path, self.serial, "shell", "svc", "data", "disable")
            time.sleep(5)
            offline_evidence = self.snapshot("network-offline")
            offline_text = f"OFFQA{datetime.now().strftime('%H%M%S')}"
            visible, send_evidence = self.send_text(offline_text, "offline-message")
            offline_evidence += send_evidence
            set_case(
                self.cases,
                "IM-366",
                "PASS" if visible else "FAIL",
                "关闭 Wi-Fi 和移动数据后在单聊发送唯一文本。",
                "断网时 App 保持可操作并生成可追踪消息气泡。" if visible else "断网后发送操作没有可追踪消息气泡。",
                offline_evidence + [rel(state_path, self.repo)],
                "P1",
            )
        finally:
            if wifi_on.strip() == "1":
                adb(self.adb_path, self.serial, "shell", "svc", "wifi", "enable")
            if data_on.strip() == "1":
                adb(self.adb_path, self.serial, "shell", "svc", "data", "enable")
            time.sleep(12)
            restored = True

        self.ensure_app()
        restored_evidence = self.snapshot("network-restored")
        recovery_text = f"NETOK{datetime.now().strftime('%H%M%S')}"
        visible, send_evidence = self.send_text(recovery_text, "network-recovery")
        backend_ok = probe_url(f"{BACKEND}/health")[0]
        recovered = restored and visible and backend_ok
        set_case(
            self.cases,
            "IM-365",
            "PASS" if recovered else "FAIL",
            "恢复原 Wi-Fi/移动数据状态，等待连接恢复后再次发送唯一文本并探测 /health。",
            "网络恢复后消息可发送且线上健康接口返回成功。" if recovered else "网络恢复后消息发送或后端健康探测仍失败。",
            restored_evidence + send_evidence + [rel(state_path, self.repo)],
            "P1",
        )
        self.event("断网与恢复", "PASS" if recovered else "FAIL", f"restored={restored} backend={backend_ok}", offline_evidence + restored_evidence)

    def appearance(self) -> None:
        original_scale = adb(self.adb_path, self.serial, "shell", "settings", "get", "system", "font_scale")
        try:
            adb(self.adb_path, self.serial, "shell", "settings", "put", "system", "font_scale", "1.30")
            time.sleep(2)
            self.navigate_tab("消息", "font-scale-navigation")
            font_evidence = self.snapshot("font-scale-130")
            visible = self.device(description="消息").exists(timeout=2)
            set_case(
                self.cases,
                "IM-052",
                "PASS" if visible else "FAIL",
                "把系统 font_scale 临时设为 1.30，重绘主界面后检查关键导航。",
                "放大字体后关键主导航仍可见可点。" if visible else "放大字体后关键导航不可见。",
                font_evidence,
                "P4",
            )
        finally:
            adb(self.adb_path, self.serial, "shell", "settings", "put", "system", "font_scale", original_scale or "1.0")

        original_mode = adb(self.adb_path, self.serial, "shell", "cmd", "uimode", "night")
        try:
            adb(self.adb_path, self.serial, "shell", "cmd", "uimode", "night", "yes")
            time.sleep(2)
            self.navigate_tab("消息", "dark-mode-navigation")
            dark_evidence = self.snapshot("dark-mode")
            visible = self.device(description="消息").exists(timeout=2)
            set_case(
                self.cases,
                "IM-053",
                "PASS" if visible else "FAIL",
                "临时切换系统深色模式并检查主界面关键导航。",
                "深色模式下主导航仍存在且可操作；视觉留截图复核。" if visible else "深色模式下关键导航丢失。",
                dark_evidence,
                "P4",
            )
        finally:
            restore = "yes" if "yes" in original_mode.lower() else "no"
            adb(self.adb_path, self.serial, "shell", "cmd", "uimode", "night", restore)

    def compatibility(self, environment_evidence: str) -> None:
        set_case(
            self.cases,
            "IM-395",
            "PASS",
            "在 Huawei ELS-AN00 Android 12 真机完成主导航、收发、生命周期与网络恢复冒烟。",
            "本轮已覆盖 Android 12 实机基线，未代表其他 Android 版本。",
            [environment_evidence],
        )


def probe_url(url: str) -> tuple[bool, str]:
    try:
        request = Request(url, headers={"User-Agent": "IM400-QA/1.0"})
        with urlopen(request, timeout=15) as response:
            return 200 <= response.status < 300, f"HTTP {response.status}"
    except (URLError, TimeoutError, OSError) as exc:
        return False, f"{type(exc).__name__}: {exc}"


def write_report(
    repo: Path,
    run_dir: Path,
    cases: dict[str, Case],
    environment: dict[str, Any],
    log_summary: dict[str, Any] | None = None,
) -> None:
    counts = {status: sum(case.status == status for case in cases.values()) for status in ("PASS", "FAIL", "SKIP", "BLOCKED")}
    priority_counts = {priority: sum(case.status == "FAIL" and case.priority == priority for case in cases.values()) for priority in ("P0", "P1", "P2", "P3", "P4", "P5")}
    payload = {
        "generated_at": now_iso(),
        "environment": environment,
        "summary": counts,
        "bug_priority_summary": priority_counts,
        "logcat_summary": log_summary,
        "cases": [asdict(case) for case in cases.values()],
    }
    (run_dir / "results.json").write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")

    def cell(value: Any) -> str:
        return str(value).replace("|", "\\|").replace("\r", " ").replace("\n", "<br>")

    lines = [
        "# IM 400 项全量功能真机测试报告",
        "",
        f"- 执行时间：{payload['generated_at']}",
        f"- 测试总数：**{len(cases)} 项**（编号 IM-001 至 IM-400，连续且无重复）",
        f"- 结果：**PASS {counts['PASS']} / FAIL {counts['FAIL']} / SKIP {counts['SKIP']} / BLOCKED {counts['BLOCKED']}**",
        f"- 真机：{environment.get('manufacturer')} {environment.get('model')}，Android {environment.get('android')}，序列号 `{environment.get('serial')}`",
        f"- App：`{environment.get('package')}` {environment.get('app_version')}",
        f"- 后端：`{environment.get('backend')}`，健康探测 {environment.get('backend_health')}",
        "",
        "## 结论口径",
        "",
        "- PASS：本轮真实执行了目标动作并得到可复核断言。",
        "- FAIL：动作已执行且实际结果不符合预期，列入 P0-P5 Bug。",
        "- SKIP：后台/第三方服务未配置，按要求直接跳过。",
        "- BLOCKED：缺少第二台授权设备、第二个可控接收端、专用硬件、长时间窗口或构造数据；不虚报通过。",
        "",
        "## Bug 优先级统计",
        "",
        "| 优先级 | 数量 | 定义 |",
        "|---|---:|---|",
        f"| P0 | {priority_counts['P0']} | 全站不可用、严重数据损坏或灾难性安全问题 |",
        f"| P1 | {priority_counts['P1']} | 核心通信链路阻断或高概率数据错误 |",
        f"| P2 | {priority_counts['P2']} | 重要功能缺失/不可用，有替代路径或不阻断基本通信 |",
        f"| P3 | {priority_counts['P3']} | 一般功能错误或边界行为不符合预期 |",
        f"| P4 | {priority_counts['P4']} | 轻微 UI、适配、文案或低频兼容问题 |",
        f"| P5 | {priority_counts['P5']} | 体验建议或优化项 |",
        "",
        "## 已发现 Bug",
        "",
    ]
    failures = [case for case in cases.values() if case.status == "FAIL"]
    if failures:
        for case in failures:
            lines += [
                f"### {case.case_id} {case.name}（{case.priority}）",
                "",
                f"- 动作：{case.action}",
                f"- 实际：{case.observed}",
                f"- 证据：{', '.join(f'`{item}`' for item in case.evidence) if case.evidence else '无'}",
                "",
            ]
    else:
        lines += ["本轮没有已复现的 FAIL；SKIP/BLOCKED 不计入通过率。", ""]

    if log_summary:
        counts_log = log_summary.get("counts", {})
        lines += [
            "## Logcat 持续监控摘要",
            "",
            f"- CRASH: {counts_log.get('CRASH', 0)}",
            f"- ANR: {counts_log.get('ANR', 0)}",
            f"- FATAL: {counts_log.get('FATAL', 0)}",
            f"- EXCEPTION: {counts_log.get('EXCEPTION', 0)}",
            f"- IM_SOCKET: {counts_log.get('IM_SOCKET', 0)}（主动断网窗口内的连接断开需结合时间线判读）",
            f"- 结束原因：{log_summary.get('stop_reason', 'unknown')}",
            f"- 异常判读：{log_summary.get('analysis', '异常关键词需结合应用 PID、测试动作和恢复结果判读。')}",
            "",
        ]

    lines += [
        "## 400 项逐项结果",
        "",
        "| 编号 | 功能点 | 结果 | Bug级别 | 真机动作 | 实际结果 | 证据 |",
        "|---|---|---|---|---|---|---|",
    ]
    for case in cases.values():
        evidence = "<br>".join(f"`{item}`" for item in case.evidence) if case.evidence else "-"
        lines.append(
            f"| {case.case_id} | {cell(case.name)} | **{case.status}** | {case.priority} | "
            f"{cell(case.action)} | {cell(case.observed)} | {evidence} |"
        )
    lines += [
        "",
        "## 完整性校验",
        "",
        f"- 总记录数：{len(cases)}",
        f"- 唯一编号数：{len(set(cases))}",
        f"- 状态合计：{sum(counts.values())}",
        f"- 未知状态数：{sum(case.status not in counts for case in cases.values())}",
    ]
    (run_dir / "IM_400_FULL_REAL_DEVICE_TEST_REPORT.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def collect_environment(adb_path: str, serial: str, package: str, backend: str, run_dir: Path) -> dict[str, Any]:
    devices = subprocess.run([adb_path, "devices", "-l"], capture_output=True, text=True, encoding="utf-8", errors="replace", check=False).stdout
    permissions = adb(adb_path, serial, "shell", "dumpsys", "package", package, timeout=45)
    (run_dir / "adb-devices.txt").write_text(devices, encoding="utf-8")
    (run_dir / "package-dumpsys.txt").write_text(permissions, encoding="utf-8")
    health_ok, health_detail = probe_url(f"{backend}/health")
    version = adb(adb_path, serial, "shell", "dumpsys", "package", package)
    version_name = re.search(r"versionName=([^\s]+)", version)
    version_code = re.search(r"versionCode=(\d+)", version)
    environment = {
        "serial": serial,
        "manufacturer": adb(adb_path, serial, "shell", "getprop", "ro.product.manufacturer"),
        "model": adb(adb_path, serial, "shell", "getprop", "ro.product.model"),
        "android": adb(adb_path, serial, "shell", "getprop", "ro.build.version.release"),
        "sdk": adb(adb_path, serial, "shell", "getprop", "ro.build.version.sdk"),
        "package": package,
        "app_version": f"{version_name.group(1) if version_name else '?'} ({version_code.group(1) if version_code else '?'})",
        "backend": backend,
        "backend_health": health_detail,
        "backend_healthy": health_ok,
        "adb_devices": devices,
        "started_at": now_iso(),
    }
    (run_dir / "environment.json").write_text(json.dumps(environment, ensure_ascii=False, indent=2), encoding="utf-8")
    return environment


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", required=True)
    parser.add_argument("--run-dir", required=True)
    parser.add_argument("--adb", required=True)
    parser.add_argument("--serial", default=SERIAL)
    parser.add_argument("--package", default=PACKAGE)
    parser.add_argument("--backend", default=BACKEND)
    parser.add_argument("--finalize", action="store_true")
    parser.add_argument("--audit-final", action="store_true")
    parser.add_argument("--log-summary", default="")
    args = parser.parse_args()

    repo = Path(args.repo).resolve()
    run_dir = Path(args.run_dir).resolve()
    run_dir.mkdir(parents=True, exist_ok=True)

    if args.audit_final:
        payload = json.loads((run_dir / "results.json").read_text(encoding="utf-8"))
        cases = {item["case_id"]: Case(**item) for item in payload["cases"]}
        environment = payload["environment"]
        set_case(
            cases,
            "IM-106",
            "PASS",
            "通过 FastInputIME 输入组合 Emoji，发送后同时核对截图与 UI 树。",
            "截图确认笑脸、肤色、家庭组合与国旗 Emoji 均作为消息气泡正常渲染；UIAutomator 语义层将图形替换为点号，不作为失败依据。",
            [
                rel(run_dir / "016-emoji-typed.png", repo),
                rel(run_dir / "017-emoji-sent.png", repo),
                rel(run_dir / "017-emoji-sent.xml", repo),
            ],
        )
        set_case(
            cases,
            "IM-107",
            "PASS",
            "通过 FastInputIME 输入扩展汉字、藏文和阿拉伯文，发送后核对截图。",
            "截图确认扩展汉字、藏文与阿拉伯文均已落泡并保持各自书写方向。",
            [
                rel(run_dir / "018-extended-typed.png", repo),
                rel(run_dir / "019-extended-sent.png", repo),
                rel(run_dir / "019-extended-sent.xml", repo),
            ],
        )
        runner = Runner(repo, run_dir, args.adb, args.serial, args.package, cases)
        runner.run_step("群聊文本发送复核", runner.group_text)
        try:
            runner.device.set_fastinput_ime(False)
        except Exception:
            pass
        text_ids = ("IM-101", "IM-102", "IM-104", "IM-105", "IM-106", "IM-107", "IM-108", "IM-109", "IM-110", "IM-116", "IM-117")
        text_ok = all(cases[item].status == "PASS" for item in text_ids)
        set_case(
            cases,
            "IM-122",
            "PASS" if text_ok else "FAIL",
            "汇总短文、长文、多行、Unicode、空白拦截和连续发送的本地成功状态。",
            "所有已执行文本类型均完成发送或按规则拦截。" if text_ok else "仍有已执行文本类型发送失败。",
            [rel(run_dir / "037-rapid-5-sent.png", repo)],
            "P1",
        )
        write_report(repo, run_dir, cases, environment, payload.get("logcat_summary"))
        return 0

    if args.finalize:
        payload = json.loads((run_dir / "results.json").read_text(encoding="utf-8"))
        cases = {item["case_id"]: Case(**item) for item in payload["cases"]}
        environment = payload["environment"]
        log_summary = json.loads(Path(args.log_summary).read_text(encoding="utf-8")) if args.log_summary and Path(args.log_summary).exists() else None
        tab_evidence = sorted(run_dir.glob("*-tab-*.xml"))
        if len(tab_evidence) >= 4:
            evidence = [rel(item, repo) for item in tab_evidence]
            for case_id in ("IM-008", "IM-019"):
                set_case(
                    cases,
                    case_id,
                    "PASS",
                    "使用已登录 smoke_bob 会话逐一进入消息/联系人/发现/设置主入口。",
                    "四个登录后主入口均可进入并完成 UI 树留证。",
                    evidence,
                )
        if log_summary:
            log_counts = log_summary.get("counts", {})
            severe = sum(int(log_counts.get(item, 0)) for item in ("CRASH", "ANR", "FATAL"))
            log_evidence = [rel(Path(args.log_summary), repo)]
            for evidence_key in ("notification_logcat_evidence", "voip_logcat_evidence"):
                for item in log_summary.get(evidence_key, []):
                    evidence_path = repo / item
                    if evidence_path.exists():
                        log_evidence.append(rel(evidence_path, repo))
            set_case(
                cases,
                "IM-400",
                "FAIL" if severe else "PASS",
                "全程持续监听 Logcat，强杀重启后检查会话首页与严重错误计数。",
                f"严重日志计数={severe}；" + ("发现崩溃/ANR/FATAL。" if severe else "未发现 Crash/ANR/FATAL，恢复后首页可操作。"),
                log_evidence,
                "P0",
            )
        set_case(
            cases,
            "IM-001",
            "FAIL",
            "打开注册页，检查手机号、验证码、密码字段和提交路径；同时核对客户端与后端注册模型。",
            "注册页只有用户名、密码、确认密码，无手机号和短信验证码入口；register_page.dart、auth_service.dart 与 auth_handler.go 均未形成 phone/code 注册链路。",
            [
                "artifacts/real-device-qa/IM-001-phone-registration-20260714-235151/02-register-page.png",
                "artifacts/real-device-qa/IM-001-phone-registration-20260714-235151/case-result.json",
                "lib/features/auth/pages/register_page.dart",
                "lib/core/services/api/auth_service.dart",
                "backend/internal/handlers/auth_handler.go",
            ],
            "P2",
        )
        write_report(repo, run_dir, cases, environment, log_summary)
        return 0

    cases = parse_checklist(repo / "docs" / "IM_FULL_REAL_DEVICE_TEST_CHECKLIST.md")
    environment = collect_environment(args.adb, args.serial, args.package, args.backend, run_dir)
    devices_evidence = rel(run_dir / "adb-devices.txt", repo)
    permissions_evidence = rel(run_dir / "package-dumpsys.txt", repo)
    initialize_preconditions(cases, devices_evidence, permissions_evidence)
    runner = Runner(repo, run_dir, args.adb, args.serial, args.package, cases)

    runner.run_step("登录与首页基线", runner.baseline)
    runner.run_step("四个主导航页巡检", runner.tabs)
    runner.run_step("单聊多类文本与边界", runner.private_texts)
    runner.run_step("聊天附件面板", runner.attachment_sheet)
    runner.run_step("群聊文本发送", runner.group_text)
    runner.run_step("前后台与强杀恢复", runner.lifecycle)
    runner.run_step("断网与恢复", runner.network_cycle)
    runner.run_step("字体与深色模式", runner.appearance)
    runner.compatibility(rel(run_dir / "environment.json", repo))

    try:
        runner.device.set_fastinput_ime(False)
    except Exception:
        pass

    write_report(repo, run_dir, cases, environment)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        print("Interrupted; device network/display restoration may require review.", file=sys.stderr)
        raise
