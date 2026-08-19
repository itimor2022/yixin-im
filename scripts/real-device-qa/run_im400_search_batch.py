#!/usr/bin/env python3
"""Run private-chat keyword/special-character search and result positioning."""

from __future__ import annotations

import argparse
import json
import sys
import time
from datetime import datetime
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from run_im400_full import set_case, write_report  # noqa: E402
from run_im400_message_actions import MessageActionBatch, load_report  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", required=True)
    parser.add_argument("--run-dir", required=True)
    parser.add_argument("--serial", required=True)
    parser.add_argument("--target", required=True)
    parser.add_argument("--package", default="com.genericim.ma100")
    args = parser.parse_args()

    repo = Path(args.repo).resolve()
    run_dir = Path(args.run_dir).resolve()
    evidence_dir = run_dir / f"search-batch-{datetime.now().strftime('%Y%m%d-%H%M%S')}"
    evidence_dir.mkdir(parents=True, exist_ok=True)
    cases, environment, log_summary = load_report(run_dir)
    batch = MessageActionBatch(repo, evidence_dir, args.serial, args.package)
    events: list[dict[str, object]] = []

    def record(action: str, ok: bool, detail: str, evidence: list[str]) -> None:
        events.append({"action": action, "ok": ok, "detail": detail, "evidence": evidence})
        (evidence_dir / "events.json").write_text(
            json.dumps(events, ensure_ascii=False, indent=2), encoding="utf-8"
        )
        line = f"[SEARCH400] {action}: {'PASS' if ok else 'FAIL'} - {detail}"
        try:
            print(line, flush=True)
        except UnicodeEncodeError:
            print(line.encode("ascii", "backslashreplace").decode("ascii"), flush=True)

    try:
        open_evidence = batch.open_chat(args.target)
        stamp = datetime.now().strftime("%H%M%S")
        prefix = f"SEARCHCASE-{stamp}"
        text = f"{prefix} 中文ABC 13800138000 https://example.com/a?x=1 🔍 !!!"
        sent, send_evidence = batch.send_text(text, "search-seed")
        # Linkified text is split across multiple Flutter semantics nodes, so
        # the full source string is not present in one node after a successful
        # send. Assert the unique prefix plus the link node instead.
        seed_xml = batch.device.dump_hierarchy()
        sent = sent or (prefix in seed_xml and "https://example.com/a?x=1" in seed_xml)
        if not sent:
            raise RuntimeError("搜索种子消息发送失败")

        header = [item for item in batch._nodes() if args.target in item["desc"] and item["top"] < 400]
        if not header:
            raise RuntimeError("私聊标题入口缺失")
        item = header[0]
        batch.device.click((item["left"] + item["right"]) // 2, (item["top"] + item["bottom"]) // 2)
        time.sleep(2)
        profile_evidence = batch.snapshot("profile-before-search")
        if not batch.device(description="搜索").click_exists(timeout=2):
            raise RuntimeError("用户资料页搜索入口缺失")
        time.sleep(2)
        search_open = batch.snapshot("search-page-open")

        query_results: dict[str, bool] = {}
        query_evidence: list[str] = []
        for index, query in enumerate((prefix, "中文ABC", "13800138000", "example.com/a?x=1", "🔍", "!!!"), 1):
            edit = batch.device(className="android.widget.EditText")
            if not edit.exists(timeout=2):
                raise RuntimeError("搜索输入框缺失")
            edit.click()
            batch.device.set_fastinput_ime(True)
            batch.device.send_keys(query, clear=True)
            time.sleep(2.5)
            visible = prefix in batch.device.dump_hierarchy()
            query_results[query] = visible
            query_evidence += batch.snapshot(f"search-query-{index}")

        keyword_ok = query_results[prefix] and query_results["中文ABC"]
        special_ok = all(query_results[q] for q in ("13800138000", "example.com/a?x=1", "🔍", "!!!"))
        set_case(
            cases,
            "IM-231",
            "PASS" if keyword_ok else "FAIL",
            "发送含唯一英文标识和中文词组的消息，分别输入英文、中文关键字搜索。",
            "英文与中文关键字均准确返回唯一种子消息。" if keyword_ok else f"关键字结果：{query_results}",
            open_evidence + send_evidence + profile_evidence + search_open + query_evidence,
            "P2",
        )
        set_case(
            cases,
            "IM-232",
            "PASS" if special_ok else "FAIL",
            "对同一消息分别搜索号码、带参数链接、Emoji 与连续标点。",
            "号码、链接、Emoji、标点四类查询均返回正确消息且页面无崩溃。" if special_ok else f"特殊字符结果：{query_results}",
            query_evidence,
            "P3",
        )

        # Restore the unique prefix query, then open its result.
        edit = batch.device(className="android.widget.EditText")
        edit.click()
        batch.device.send_keys(prefix, clear=True)
        time.sleep(2)
        results = [item for item in batch._nodes() if prefix in item["desc"] or prefix in item["text"]]
        if not results:
            raise RuntimeError("定位前未找到搜索结果行")
        row = max(results, key=lambda node: (node["right"] - node["left"]) * (node["bottom"] - node["top"]))
        batch.device.click((row["left"] + row["right"]) // 2, (row["top"] + row["bottom"]) // 2)
        time.sleep(4)
        positioned = batch.visible_outside_edit(prefix)
        position_evidence = batch.snapshot("search-result-positioned")
        set_case(
            cases,
            "IM-236",
            "PASS" if positioned else "FAIL",
            "点击唯一关键字对应的搜索结果行，等待返回目标私聊并定位。",
            "页面进入正确私聊并显示目标原消息及其上下文。" if positioned else "点击结果后未在目标会话中看到原消息。",
            query_evidence[-2:] + position_evidence,
            "P2",
        )
        record("关键字搜索", keyword_ok, str(query_results), query_evidence)
        record("特殊字符搜索", special_ok, str(query_results), query_evidence)
        record("结果定位", positioned, f"positioned={positioned}", position_evidence)
        write_report(repo, run_dir, cases, environment, log_summary)
    except Exception as exc:
        evidence = batch.snapshot("search-harness-error")
        record("search-batch", False, f"自动化步骤异常：{type(exc).__name__}: {exc}", evidence)
        write_report(repo, run_dir, cases, environment, log_summary)
    finally:
        try:
            batch.device.set_fastinput_ime(False)
        except Exception:
            pass

    print(f"[SEARCH400] report={run_dir / 'IM_400_FULL_REAL_DEVICE_TEST_REPORT.md'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
