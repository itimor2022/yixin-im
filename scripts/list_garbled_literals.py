from pathlib import Path
import re

FILES = [
    "lib/app.dart",
    "lib/core/services/call_service.dart",
    "lib/features/chat/providers/message_provider.dart",
    "backend/internal/handlers/call_handler.go",
    "backend/internal/handlers/meeting_handler.go",
]

SUSPICIOUS = set(
    "闂鏆妗瑙鍒鐢缂鎴顫閲鍙娑璇鎺娆欐堕瀹绛锛銆鈥鑱绾鍚鐣娼閫鏁鐗鐧灏钃绗鐝澧鍐顕妫娲焽瀣鍎樀鍦鐑濮炲"
    "閸閹閺閻閼閽閾閿鐚鐩鐫鐭鐮鐯鐰鐱鐲鐳鐴鐵鐶鐷鐸鐹鐺鐻鐼鐽鐾鐿鎴鎵鎶鎷鎸鎹鎺鎻鎼鎽鎾鎿"
)

string_re = re.compile(r"""(['"])(.*?)(?<!\\)\1""")

out = []
for file in FILES:
    path = Path(file)
    out.append(f"## {file}")
    text = path.read_text(encoding="utf-8")
    for lineno, line in enumerate(text.splitlines(), start=1):
        for m in string_re.finditer(line):
            s = m.group(2)
            if any(ch in SUSPICIOUS for ch in s):
                out.append(f"{lineno}: {s}")
    out.append("")

Path("docs/garbled_literals.txt").write_text("\n".join(out), encoding="utf-8")
print("written docs/garbled_literals.txt")
