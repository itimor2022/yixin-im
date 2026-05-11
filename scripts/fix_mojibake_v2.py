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
    "闂鏆妗瑙鍒鐢缂鎴顫閲鍙娑璇鎺娆欐堕瀹绛锛銆鈥鑱绾鍚鐣娼閫鏁鐗鐧灏钃绗鐝澧鍐顕妫娲焽瀣鍎樀鍦鐑濮炲"
    "閸閹閺閻閼閽閾閿鐚鐩鐫鐭鐮鐯鐰鐱鐲鐳鐴鐵鐶鐷鐸鐹鐺鐻鐼鐽鐾鐿"
    "姘姣姤姥姦姧咨姩姪姫姬姭姮姯姰姱姲姳姴姵姶姷姸姹姺姻姼姽姾姿"
    "鎴鎵鎶鎷鎸鎹鎺鎻鎼鎽鎾鎿鏀鏁鏂鏃鏄昀時晀晁晄晒晈晊晌晍晎晏"
    "傛傜傚傳侀仛氬櫒鐢ㄦ埛鏈壘鍒版暟鎹簱绯荤粺閫氳瘽閿欒"
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
