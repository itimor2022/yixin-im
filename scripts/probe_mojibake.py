from __future__ import annotations

import heapq
import re
from pathlib import Path

SUSPICIOUS = set(
    chr(c)
    for c in [
        0x3006, 0x5987, 0x6b06, 0x6b39, 0x6d32, 0x6f7c, 0x6fee, 0x7023,
        0x7029, 0x704f, 0x708a, 0x713d, 0x7459, 0x7487, 0x7b17, 0x7b1b,
        0x7efe, 0x837b, 0x9225, 0x9286, 0x9350, 0x9352, 0x9359, 0x935a,
        0x9366, 0x93b4, 0x93ba, 0x93c1, 0x93c6, 0x9411, 0x9417, 0x941d,
        0x9422, 0x9423, 0x9427, 0x9471, 0x9483, 0x95ab, 0x95b2, 0x95c2,
        0x986b,
    ]
)
ENCODINGS = ["utf-8", "gb18030", "gbk", "cp936", "latin1", "cp1252"]
LATIN_MOJIBAKE_MARKERS = "".join(chr(c) for c in [0x00C3, 0x00C2, 0x00D0, 0x00D1, 0x00D8, 0x00DE])


def score(text: str) -> float:
    cjk = sum(1 for ch in text if "\u4e00" <= ch <= "\u9fff")
    ascii_ok = sum(1 for ch in text if 32 <= ord(ch) <= 126)
    suspicious = sum(1 for ch in text if ch in SUSPICIOUS)
    replacement = text.count("\ufffd") + text.count("?")
    weird = len(re.findall(f"[{re.escape(LATIN_MOJIBAKE_MARKERS)}]", text))
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
