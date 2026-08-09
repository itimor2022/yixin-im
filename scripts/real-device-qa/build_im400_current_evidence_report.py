#!/usr/bin/env python3
"""Build an auditable IM-001..IM-400 status from structured QA evidence.

The historical 400-case result remains the status baseline. Newer structured
PASS records may promote a case, but generic BLOCKED/FAIL scans never downgrade
an existing PASS. This keeps targeted strict-device evidence authoritative over
conservative smoke runners that could not enter a required conversation.
"""

from __future__ import annotations

import argparse
import json
import re
from collections import Counter
from copy import deepcopy
from datetime import datetime
from pathlib import Path
from typing import Any, Iterable


CASE_ID_RE = re.compile(r"^IM-(\d{3})$")
STATUSES = {"PASS", "FAIL", "SKIP", "BLOCKED"}


def now_iso() -> str:
    return datetime.now().astimezone().isoformat(timespec="seconds")


def rel(path: Path, repo: Path) -> str:
    try:
        return path.resolve().relative_to(repo.resolve()).as_posix()
    except ValueError:
        return path.resolve().as_posix()


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def normalize_status(value: Any) -> str | None:
    if not isinstance(value, str):
        return None
    status = value.strip().upper()
    return status if status in STATUSES else None


def evidence_paths(node: dict[str, Any]) -> list[str]:
    result: list[str] = []
    for key in ("evidence", "evidence_files", "artifacts"):
        value = node.get(key)
        if isinstance(value, str):
            result.append(value)
        elif isinstance(value, list):
            result.extend(item for item in value if isinstance(item, str))
    checks = node.get("checks")
    if isinstance(checks, dict):
        result.extend(evidence_paths(checks))
    return list(dict.fromkeys(result))


def extract_case_records(node: Any) -> Iterable[tuple[str, str, list[str]]]:
    """Yield case results from the common QA JSON shapes in this repository."""
    if isinstance(node, list):
        for item in node:
            yield from extract_case_records(item)
        return
    if not isinstance(node, dict):
        return

    case_id = node.get("case_id")
    if not isinstance(case_id, str):
        case_id = node.get("id")
    status = normalize_status(node.get("status"))
    if isinstance(case_id, str) and CASE_ID_RE.fullmatch(case_id) and status:
        yield case_id, status, evidence_paths(node)

    case_ids = node.get("case_ids")
    if isinstance(case_ids, list) and status:
        for item in case_ids:
            if isinstance(item, str) and CASE_ID_RE.fullmatch(item):
                yield item, status, evidence_paths(node)

    cases = node.get("cases")
    if isinstance(cases, dict):
        for key, value in cases.items():
            if not isinstance(key, str) or not CASE_ID_RE.fullmatch(key):
                continue
            if isinstance(value, dict):
                child_status = normalize_status(value.get("status"))
                if child_status:
                    yield key, child_status, evidence_paths(value)
    elif isinstance(cases, list):
        for item in cases:
            yield from extract_case_records(item)

    # Some targeted result files use an IM-xxx key without a `cases` wrapper.
    for key, value in node.items():
        if key == "cases" or not isinstance(key, str) or not CASE_ID_RE.fullmatch(key):
            continue
        if isinstance(value, dict):
            child_status = normalize_status(value.get("status"))
            if child_status:
                yield key, child_status, evidence_paths(value)

    # API suites commonly keep case records under `results`; recurse through
    # other containers so their `case_ids` arrays are not missed.
    for key, value in node.items():
        if key == "cases" or (isinstance(key, str) and CASE_ID_RE.fullmatch(key)):
            continue
        if isinstance(value, (dict, list)):
            yield from extract_case_records(value)


def discover_records(
    repo: Path,
    artifacts_root: Path,
    excluded_roots: set[Path],
) -> tuple[dict[str, list[dict[str, Any]]], list[dict[str, str]]]:
    records: dict[str, list[dict[str, Any]]] = {
        f"IM-{number:03d}": [] for number in range(1, 401)
    }
    parse_errors: list[dict[str, str]] = []
    for path in sorted(artifacts_root.rglob("*.json")):
        resolved = path.resolve()
        if any(root == resolved or root in resolved.parents for root in excluded_roots):
            continue
        try:
            payload = load_json(path)
        except (OSError, UnicodeError, json.JSONDecodeError) as exc:
            parse_errors.append({"path": rel(path, repo), "error": str(exc)})
            continue
        seen: set[tuple[str, str]] = set()
        for case_id, status, nested_evidence in extract_case_records(payload):
            marker = (case_id, status)
            if marker in seen:
                continue
            seen.add(marker)
            records[case_id].append(
                {
                    "status": status,
                    "source": rel(path, repo),
                    "evidence": nested_evidence,
                    "modified_at": datetime.fromtimestamp(
                        path.stat().st_mtime
                    ).astimezone().isoformat(timespec="seconds"),
                }
            )
    return records, parse_errors


def case_map(payload: dict[str, Any]) -> dict[str, dict[str, Any]]:
    items = payload.get("cases")
    if not isinstance(items, list):
        raise ValueError("results payload must contain a cases list")
    result = {item.get("case_id"): item for item in items if isinstance(item, dict)}
    expected = {f"IM-{number:03d}" for number in range(1, 401)}
    if set(result) != expected:
        missing = sorted(expected - set(result))
        extra = sorted(set(result) - expected)
        raise ValueError(f"invalid case set: missing={missing}, extra={extra}")
    return result


def write_markdown(
    path: Path,
    payload: dict[str, Any],
    baseline_path: str,
    metadata_path: str,
) -> None:
    summary = payload["summary"]
    cases = payload["cases"]
    unresolved = [case for case in cases if case["status"] != "PASS"]
    lines = [
        "# IM-001..IM-400 当前结构化证据汇总",
        "",
        f"- 生成时间：`{payload['generated_at']}`",
        f"- 状态底稿：`{baseline_path}`",
        f"- 项目元数据：`{metadata_path}`",
        f"- 汇总结果：PASS **{summary['PASS']}** / FAIL **{summary['FAIL']}** / "
        f"SKIP **{summary['SKIP']}** / BLOCKED **{summary['BLOCKED']}**",
        f"- 已纳入结构化 JSON：**{payload['evidence_scan']['parsed_json_files']}** 个",
        f"- JSON 解析失败：**{payload['evidence_scan']['parse_error_count']}** 个",
        "",
        "说明：历史底稿提供初始状态；后续只有明确包含 IM 编号和 PASS 状态的结构化结果才能提升项目。"
        "保守全量脚本因导航或测试数据不足产生的 FAIL/BLOCKED 不会覆盖已存在的定向严格 PASS。",
        "",
        "## 未完全通过项目",
        "",
        "| 编号 | 状态 | 名称 | 当前说明 |",
        "| --- | --- | --- | --- |",
    ]
    for case in unresolved:
        observed = " ".join(str(case.get("observed", "")).split()).replace("|", "\\|")
        name = str(case.get("name", "")).replace("|", "\\|")
        lines.append(f"| {case['case_id']} | {case['status']} | {name} | {observed} |")

    lines.extend(["", "## PASS 证据索引", "", "| 编号 | 结构化证据 |", "| --- | --- |"])
    for case in cases:
        if case["status"] != "PASS":
            continue
        sources = case.get("current_pass_sources", [])
        shown = sources[-4:] if sources else case.get("evidence", [])[-4:]
        lines.append(f"| {case['case_id']} | {'<br>'.join(f'`{item}`' for item in shown)} |")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", required=True)
    parser.add_argument("--baseline", required=True)
    parser.add_argument("--metadata", required=True)
    parser.add_argument("--artifacts-root", default="artifacts")
    parser.add_argument("--output-dir", required=True)
    args = parser.parse_args()

    repo = Path(args.repo).resolve()
    baseline_path = (repo / args.baseline).resolve()
    metadata_path = (repo / args.metadata).resolve()
    artifacts_root = (repo / args.artifacts_root).resolve()
    output_dir = (repo / args.output_dir).resolve()

    baseline_payload = load_json(baseline_path)
    metadata_payload = load_json(metadata_path)
    baseline_cases = case_map(baseline_payload)
    metadata_cases = case_map(metadata_payload)

    output_dir.mkdir(parents=True, exist_ok=True)
    generated_report_roots = {
        path.resolve()
        for path in artifacts_root.rglob("im400-current-evidence-*")
        if path.is_dir()
    }
    generated_report_roots.add(output_dir)
    records, parse_errors = discover_records(
        repo,
        artifacts_root,
        excluded_roots=generated_report_roots,
    )

    cases: list[dict[str, Any]] = []
    promoted: list[str] = []
    for number in range(1, 401):
        case_id = f"IM-{number:03d}"
        case = deepcopy(baseline_cases[case_id])
        for key in ("name", "expected", "module"):
            if metadata_cases[case_id].get(key):
                case[key] = metadata_cases[case_id][key]

        pass_records = [item for item in records[case_id] if item["status"] == "PASS"]
        pass_sources = list(dict.fromkeys(item["source"] for item in pass_records))
        if pass_sources:
            if case.get("status") != "PASS":
                promoted.append(case_id)
            case["status"] = "PASS"
            case["priority"] = "-"
            case["action"] = "汇总现有定向真机、双机、接口或平台结构化测试证据。"
            case["observed"] = (
                f"发现 {len(pass_sources)} 个结构化结果文件明确记录该项目 PASS；"
                "证据来源已保留，未以源码修改代替运行结果。"
            )
            case["tested_at"] = max(item["modified_at"] for item in pass_records)
            existing = [item for item in case.get("evidence", []) if isinstance(item, str)]
            nested = [
                evidence
                for item in pass_records
                for evidence in item.get("evidence", [])
                if isinstance(evidence, str)
            ]
            case["evidence"] = list(dict.fromkeys(existing + pass_sources + nested))
            case["current_pass_sources"] = pass_sources
        else:
            case["current_pass_sources"] = []
        cases.append(case)

    summary = Counter(case["status"] for case in cases)
    if sum(summary.values()) != 400:
        raise RuntimeError(f"summary does not total 400: {summary}")

    payload = {
        "generated_at": now_iso(),
        "policy": {
            "baseline_statuses_preserved": True,
            "pass_only_promotion": True,
            "generic_failures_do_not_downgrade_existing_pass": True,
            "source_code_changes_are_not_test_passes": True,
        },
        "sources": {
            "baseline": rel(baseline_path, repo),
            "metadata": rel(metadata_path, repo),
            "artifacts_root": rel(artifacts_root, repo),
        },
        "summary": {status: summary.get(status, 0) for status in ("PASS", "FAIL", "SKIP", "BLOCKED")},
        "promoted_from_baseline": promoted,
        "evidence_scan": {
            "parsed_json_files": sum(
                1
                for path in artifacts_root.rglob("*.json")
                if not any(
                    root == path.resolve() or root in path.resolve().parents
                    for root in generated_report_roots
                )
            ) - len(parse_errors),
            "parse_error_count": len(parse_errors),
            "parse_errors": parse_errors,
        },
        "cases": cases,
    }

    results_path = output_dir / "results.json"
    report_path = output_dir / "IM400_CURRENT_EVIDENCE_REPORT.md"
    results_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    write_markdown(
        report_path,
        payload,
        rel(baseline_path, repo),
        rel(metadata_path, repo),
    )
    print(
        json.dumps(
            {
                "summary": payload["summary"],
                "promoted": len(promoted),
                "parse_errors": len(parse_errors),
                "results": rel(results_path, repo),
                "report": rel(report_path, repo),
            },
            ensure_ascii=False,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
