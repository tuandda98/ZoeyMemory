#!/usr/bin/env bash
# Bật bộ kyuc cho một repo: openspec init + .claude/kyuc.json + docs/nhatky/ + khối CLAUDE.md.
# IDEMPOTENT: chạy lại không ghi đè thứ đã có. Không commit — việc đó để Claude/chủ dự án làm.
#
# Dùng: bash khoi-tao.sh [đường dẫn repo]   (mặc định: $CLAUDE_PROJECT_DIR hoặc git toplevel hoặc pwd)
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAU="$HERE/mau"
ROOT="${1:-${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}}"
ROOT="$(cd "$ROOT" 2>/dev/null && pwd)" || { echo "✗ không vào được thư mục: $1"; exit 1; }
cd "$ROOT" || exit 1

ok()   { printf '✓ %s\n' "$*"; }
warn() { printf '⚠ %s\n' "$*"; }
skip() { printf '· %s\n' "$*"; }

echo "# kyuc khởi tạo — $ROOT"
echo

# 1. git
if [ -d .git ]; then skip "git đã có"; else git init -q && ok "git init"; fi

# 2. openspec CLI
if command -v openspec >/dev/null 2>&1; then
  ok "openspec CLI $(openspec --version 2>/dev/null)"
elif command -v npm >/dev/null 2>&1; then
  echo "· đang cài openspec CLI…"
  if npm install -g @fission-ai/openspec@latest >/dev/null 2>&1; then
    ok "openspec CLI $(openspec --version 2>/dev/null)"
  else
    warn "không cài được openspec CLI — cài tay: npm i -g @fission-ai/openspec@latest"
  fi
else
  warn "thiếu npm nên không cài được openspec CLI (cần Node 20.19+)"
fi

# 3. openspec init (không tương tác, tiếng Việt, chỉ tạo lệnh cho Claude Code)
if [ -d openspec ]; then
  skip "openspec/ đã có"
elif command -v openspec >/dev/null 2>&1; then
  if openspec init --tools claude --language vi --no-animation . >/dev/null 2>&1; then
    ok "openspec init (tools=claude, language=vi)"
  else
    warn "openspec init lỗi — chạy tay: openspec init --tools claude --language vi"
  fi
fi

# 4. .claude/kyuc.json (bỏ key chú thích `_`, điền tên = tên thư mục)
mkdir -p .claude
if [ -f .claude/kyuc.json ]; then
  skip ".claude/kyuc.json đã có"
else
  python3 - "$MAU/kyuc.json" ".claude/kyuc.json" "$(basename "$ROOT")" <<'PY' && ok ".claude/kyuc.json" || warn "không tạo được .claude/kyuc.json"
import json, sys
src, dst, ten = sys.argv[1:4]
c = json.load(open(src, encoding="utf-8"))
def strip(o):
    if isinstance(o, dict):
        return {k: strip(v) for k, v in o.items() if not k.startswith("_")}
    if isinstance(o, list):
        return [strip(v) for v in o]
    return o
c = strip(c)
c["ten"] = ten
with open(dst, "w", encoding="utf-8") as f:
    json.dump(c, f, ensure_ascii=False, indent=2)
    f.write("\n")
PY
fi

# 5. docs/nhatky/
cfg_get() { python3 -c "
import json
try: c=json.load(open('.claude/kyuc.json'))
except Exception: c={}
print(((c.get('nhatky') or {}).get('$1')) or '$2')" 2>/dev/null; }
CH="$(cfg_get cauHoi docs/nhatky/CAU_HOI.md)"
PH="$(cfg_get phien docs/nhatky/PHIEN.md)"
mkdir -p "$(dirname "$CH")" "$(dirname "$PH")"
if [ -f "$CH" ]; then skip "$CH đã có"; else
  cat > "$CH" <<'EOF'
# Nhật ký câu hỏi (tự động)

Hook `kyuc/ghi-nhat-ky.sh` tự ghi: mốc mở phiên + từng câu chủ dự án nhắn.
File này ĐƯỢC COMMIT — máy kia đọc để biết máy này vừa nhờ làm gì.

Đừng sửa tay phần tự động. Muốn ghi KẾT QUẢ một việc thì thêm dòng bắt đầu bằng `> `
ngay dưới câu tương ứng. Lý do QUYẾT ĐỊNH thì ghi ở OpenSpec (`openspec/changes/<tên>/`).
EOF
  ok "$CH"
fi
if [ -f "$PH" ]; then skip "$PH đã có"; else
  cat > "$PH" <<'EOF'
# Nhật ký phiên

Mỗi lần rời máy (`/kyuc:cuoi-ca`) thêm MỘT mục mới ở cuối, khuôn:

## YYYY-MM-DD HH:MM — nhánh `main` — máy <tên máy>
- Đang dở: …
- Vì sao dừng: …
- Chờ ai quyết gì: …
- Máy kia cần biết (thứ không đi theo git): …

Hook `dau-phien.sh` nạp mục MỚI NHẤT vào đầu phiên sau. Đừng chép lại `git log` — commit trả lời
"đã đổi gì", mục này trả lời "vì sao, và tiếp theo là gì".
EOF
  ok "$PH"
fi

# 6. CLAUDE.md — thêm khối phân vai nếu chưa có
if [ -f CLAUDE.md ] && grep -q '<!-- kyuc:start -->' CLAUDE.md; then
  skip "CLAUDE.md đã có khối kyuc"
else
  { [ -s CLAUDE.md ] && printf '\n'; cat "$MAU/CLAUDE.md"; } >> CLAUDE.md
  ok "CLAUDE.md += khối kyuc (phân vai kyuc / OpenSpec / superpowers)"
fi

# 7. .gitignore
touch .gitignore
if grep -qx '.claude/settings.local.json' .gitignore; then skip ".gitignore đã có settings.local.json"; else
  printf '.claude/settings.local.json\n' >> .gitignore; ok ".gitignore += .claude/settings.local.json"
fi

# 8. superpowers có chưa
if claude plugin list 2>/dev/null | grep -q 'superpowers@'; then
  ok "superpowers đã cài"
else
  warn "superpowers CHƯA cài. Cài: claude plugin marketplace add obra/superpowers-marketplace && claude plugin install superpowers@superpowers-marketplace"
fi

echo
echo "Xong. Hook chỉ tác dụng từ phiên sau (hoặc gõ /reload-plugins). Commit các file trên để máy kia có."
exit 0
