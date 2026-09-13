#!/usr/bin/env bash
# SessionStart + UserPromptSubmit: GHI NHẬT KÝ TỰ ĐỘNG — mốc mở phiên + từng câu chủ dự án nhắn.
#
# Nhật ký này ghi ĐƯỜNG ĐI ("chủ dự án đã hỏi gì, theo thứ tự nào"). Kết luận ("đã làm gì, vì
# sao dừng") nằm ở nhật ký phiên do /kyuc:cuoi-ca viết; lý do quyết định nằm ở OpenSpec.
# Đây là thứ duy nhất sống sót khi một phiên kết thúc đột ngột (máy sập, đóng nhầm tab).
#
# Đích: `.claude/kyuc.json` → `nhatky.cauHoi` (mặc định docs/nhatky/CAU_HOI.md). File ĐƯỢC COMMIT.
# KHÔNG có `.claude/kyuc.json` = repo chưa bật bộ này → thoát ngay, không tạo file gì.
# LUÔN exit 0: nhật ký hỏng thì kệ, không bao giờ được chặn phiên làm việc.
set -uo pipefail

ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || true)}"
[ -n "$ROOT" ] || exit 0
CFG="$ROOT/.claude/kyuc.json"
[ -f "$CFG" ] || exit 0

INPUT=$(cat 2>/dev/null || true)
[ -n "$INPUT" ] || exit 0

STAMP=$(TZ="${TZ:-Asia/Ho_Chi_Minh}" date '+%Y-%m-%d %H:%M')
TIME=$(TZ="${TZ:-Asia/Ho_Chi_Minh}" date '+%H:%M')
BRANCH=$(git -C "$ROOT" branch --show-current 2>/dev/null || echo '?')

KYUC_INPUT="$INPUT" python3 - "$ROOT" "$CFG" "$STAMP" "$TIME" "$BRANCH" <<'PY' 2>/dev/null
import json, os, sys

root, cfg_path, stamp, time_, branch = sys.argv[1:6]
try:
    cfg = json.load(open(cfg_path, encoding="utf-8"))
except Exception:
    cfg = {}
nk = cfg.get("nhatky") or {}
if nk.get("bat") is False:
    sys.exit(0)
rel = nk.get("cauHoi") or "docs/nhatky/CAU_HOI.md"
log = os.path.join(root, rel)

try:
    data = json.loads(os.environ.get("KYUC_INPUT", ""))
except Exception:
    sys.exit(0)

event = data.get("hook_event_name", "")
if event == "SessionStart":
    line = "\n## Phiên mới — %s (nhánh `%s`, %s)\n" % (stamp, branch, data.get("source", "?"))
elif event == "UserPromptSubmit":
    prompt = " ".join(str(data.get("prompt", "")).split())
    if not prompt:
        sys.exit(0)
    if len(prompt) > 600:
        prompt = prompt[:600] + "…"
    line = "- [%s] %s\n" % (time_, prompt)
else:
    sys.exit(0)

os.makedirs(os.path.dirname(log) or ".", exist_ok=True)
if not os.path.exists(log):
    with open(log, "w", encoding="utf-8") as f:
        f.write(
            "# Nhật ký câu hỏi (tự động)\n\n"
            "Hook `kyuc/ghi-nhat-ky.sh` tự ghi: mốc mở phiên + từng câu chủ dự án nhắn.\n"
            "File này ĐƯỢC COMMIT — máy kia đọc để biết máy này vừa nhờ làm gì.\n\n"
            "Đừng sửa tay phần tự động. Muốn ghi KẾT QUẢ một việc thì thêm dòng bắt đầu bằng `> `\n"
            "ngay dưới câu tương ứng. Lý do QUYẾT ĐỊNH thì ghi ở OpenSpec (`openspec/changes/<tên>/`).\n"
        )
with open(log, "a", encoding="utf-8") as f:
    f.write(line)
PY
exit 0
