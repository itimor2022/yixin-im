from pathlib import Path

path = Path("backend/internal/handlers/call_handler.go")
raw = path.read_bytes()

for enc in ("utf-8", "gb18030", "gbk", "cp936"):
    try:
        text = raw.decode(enc)
        line = text.splitlines()[131]
        print(f"[{enc}] {line}")
    except Exception as exc:
        print(f"[{enc}] ERROR: {exc}")
