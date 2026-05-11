from __future__ import annotations

import heapq
import re
from pathlib import Path

SUSPICIOUS = set("闂鏆妗瑙鍒鐢缂鎴顫閲鍙娑璇鎺娆欐堕瀹绛锛銆鈥鑱绾鍚鐣娼閫鏁鐗鐧灏钃绗鐝澧鍐顕妫娲焽瀣鍎樀鍦鐑濮炲")
ENCODINGS = ["utf-8", "gb18030", "gbk", "cp936", "latin1", "cp1252"]


def score(text: str) -> float:
    cjk = sum(1 for ch in text if "\u4e00" <= ch <= "\u9fff")
    ascii_ok = sum(1 for ch in text if 32 <= ord(ch) <= 126)
    suspicious = sum(1 for ch in text if ch in SUSPICIOUS)
    replacement = text.count("\ufffd") + text.count("?")
    weird = len(re.findall(r"[ÃÂÐÑØÞ]", text))
    return cjk * 3 + ascii_ok * 0.05 - suspicious * 4 - replacement * 2 - weird * 2


def transform_once(text: str):
    for enc in ENCODINGS:
        for dec in ENCODINGS:
            if enc == dec:
                continue
            try:
                out = text.encode(enc).decode(dec)
            except Exception:
                continue
            yield f"encode:{enc}->decode:{dec}", out


def best_candidates(text: str, depth: int = 3, limit: int = 12):
    seen = {text}
    heap = [(-score(text), 0, "origin", text)]
    out = []
    while heap and len(out) < limit:
        neg_score, cur_depth, path, cur = heapq.heappop(heap)
        out.append((-neg_score, cur_depth, path, cur))
        if cur_depth >= depth:
            continue
        for step, nxt in transform_once(cur):
            if nxt in seen:
                continue
            seen.add(nxt)
            heapq.heappush(heap, (-score(nxt), cur_depth + 1, path + " | " + step, nxt))
    return out


def main():
    path = Path("backend/internal/handlers/call_handler.go")
    line = path.read_text(encoding="utf-8").splitlines()[131]
    m = re.search(r'"([^"]+)"', line)
    text = m.group(1) if m else line
    lines = [f"ORIGINAL={text}", ""]
    for s, depth, route, candidate in best_candidates(text):
        lines.append(f"SCORE={s:.2f} DEPTH={depth}")
        lines.append(f"ROUTE={route}")
        lines.append(f"TEXT={candidate}")
        lines.append("")
    Path("docs/encoding_candidates.txt").write_text("\n".join(lines), encoding="utf-8")
    print("written docs/encoding_candidates.txt")


if __name__ == "__main__":
    main()
