from pathlib import Path
import re

text = Path("backend/internal/handlers/call_handler.go").read_text(encoding="utf-8").splitlines()[131]
m = re.search(r'"([^"]+)"', text)
s = m.group(1)
prefix = s[:4]
lines = [f"full={s}", f"prefix={prefix}"]
for enc in ("gb18030", "gbk", "cp936", "utf-8", "latin1"):
    for dec in ("gb18030", "gbk", "cp936", "utf-8", "latin1"):
        if enc == dec:
            continue
        try:
            fixed = prefix.encode(enc).decode(dec)
        except Exception:
            continue
        lines.append(f"{enc}->{dec}: {fixed!r}")

Path("docs/prefix_transform_candidates.txt").write_text("\n".join(lines), encoding="utf-8")
print("written docs/prefix_transform_candidates.txt")
