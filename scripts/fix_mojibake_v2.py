from __future__ import annotations

from functools import lru_cache
from pathlib import Path
from typing import Iterable

TARGET_FILES = [
    Path("lib/app.dart"),
    Path("lib/core/services/call_service.dart"),
    Path("lib/features/chat/providers/message_provider.dart"),
    Path("backend/internal/handlers/call_handler.go"),
    Path("backend/internal/handlers/meeting_handler.go"),
]

SUSPICIOUS = set(
    chr(c)
    for c in [
        0x3006, 0x50a8, 0x509c, 0x4f80, 0x4edb, 0x57db, 0x5987, 0x59d8,
        0x59e3, 0x59e4, 0x59e5, 0x59e6, 0x59e7, 0x54a8, 0x59e9, 0x59ea,
        0x59eb, 0x59ec, 0x59ed, 0x59ee, 0x59ef, 0x59f0, 0x59f1, 0x59f2,
        0x59f3, 0x59f4, 0x59f5, 0x59f6, 0x59f7, 0x59f8, 0x59f9, 0x59fa,
        0x59fb, 0x59fc, 0x59fd, 0x59fe, 0x59ff, 0x612c, 0x66d6, 0x669f,
        0x6ad2, 0x6b06, 0x6b12, 0x6b39, 0x6c18, 0x6c2c, 0x6c33, 0x6d32,
        0x6f7c, 0x6fee, 0x7023, 0x7029, 0x704f, 0x708a, 0x713d, 0x7459,
        0x7487, 0x763d, 0x7b17, 0x7b1b, 0x7c31, 0x7c9c, 0x7cba, 0x7efe,
        0x837b, 0x9225, 0x9286, 0x934a, 0x9350, 0x9352, 0x9359, 0x935a,
        0x9366, 0x93b4, 0x93b5, 0x93b6, 0x93b7, 0x93b8, 0x93b9, 0x93ba,
        0x93bb, 0x93bc, 0x93bd, 0x93be, 0x93bf, 0x93c1, 0x93c6, 0x93c8,
        0x9411, 0x9417, 0x941a, 0x941d, 0x9422, 0x9423, 0x9427, 0x9429,
        0x942b, 0x942d, 0x942e, 0x942f, 0x9430, 0x9431, 0x9432, 0x9433,
        0x9434, 0x9435, 0x9436, 0x9437, 0x9438, 0x9439, 0x943a, 0x943b,
        0x943c, 0x943d, 0x943e, 0x943f, 0x9471, 0x9483, 0x95ab, 0x95b2,
        0x95b8, 0x95b9, 0x95ba, 0x95bb, 0x95bc, 0x95bd, 0x95be, 0x95bf,
        0x95c2, 0x986b, 0xe041, 0xe386, 0xe1e4,
    ]
)

SOURCE_ENCODINGS = ("gb18030", "gbk", "cp936")


def suspicious_count(text: str) -> int:
    return sum(ch in SUSPICIOUS for ch in text)


def piece_score(text: str) -> float:
    cjk = sum("\u4e00" <= ch <= "\u9fff" for ch in text)
    suspicious = suspicious_count(text)
    replacement = text.count("\ufffd") + text.count("?")
    ascii_ok = sum(32 <= ord(ch) <= 126 for ch in text)
    return cjk * 2.0 + ascii_ok * 0.05 - suspicious * 3.0 - replacement * 2.0


def candidate_transforms(segment: str) -> Iterable[str]:
    yielded = set()
    for enc in SOURCE_ENCODINGS:
        try:
            transformed = segment.encode(enc).decode("utf-8")
        except Exception:
            continue
        if transformed not in yielded:
            yielded.add(transformed)
            yield transformed


def repair_line(line: str) -> str:
    n = len(line)

    @lru_cache(maxsize=None)
    def solve(i: int) -> tuple[float, str]:
        if i >= n:
            return 0.0, ""

        best_score, best_text = solve(i + 1)
        best_score += piece_score(line[i])
        best_text = line[i] + best_text

        for j in range(i + 2, min(n, i + 28) + 1):
            segment = line[i:j]
            if suspicious_count(segment) == 0:
                continue
            for transformed in candidate_transforms(segment):
                if transformed == segment:
                    continue
                if suspicious_count(transformed) >= suspicious_count(segment):
                    continue
                if "\ufffd" in transformed:
                    continue
                tail_score, tail_text = solve(j)
                total_score = piece_score(transformed) + tail_score
                if total_score > best_score + 0.25:
                    best_score = total_score
                    best_text = transformed + tail_text
        return best_score, best_text

    return solve(0)[1]


def process_file(path: Path, apply: bool) -> tuple[int, bool]:
    original = path.read_text(encoding="utf-8")
    lines = original.splitlines(keepends=True)
    changed = 0
    out_lines: list[str] = []
    for line in lines:
        if suspicious_count(line) == 0:
            out_lines.append(line)
            continue
        stripped_newline = ""
        core = line
        if line.endswith("\r\n"):
            core = line[:-2]
            stripped_newline = "\r\n"
        elif line.endswith("\n"):
            core = line[:-1]
            stripped_newline = "\n"
        fixed = repair_line(core)
        if fixed != core:
            changed += 1
        out_lines.append(fixed + stripped_newline)
    if changed and apply:
        path.write_text("".join(out_lines), encoding="utf-8")
    return changed, changed > 0


def main(apply: bool = False) -> None:
    files_changed = 0
    lines_changed = 0
    changed_paths: list[str] = []
    for path in TARGET_FILES:
        changed_count, did_change = process_file(path, apply)
        if did_change:
            files_changed += 1
            lines_changed += changed_count
            changed_paths.append(str(path))
    print(f"files_changed={files_changed}")
    print(f"lines_changed={lines_changed}")
    for item in changed_paths:
        print(item)


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    main(apply=args.apply)
