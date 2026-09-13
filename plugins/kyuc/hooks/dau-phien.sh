#!/usr/bin/env bash
# SessionStart: ĐỒNG BỘ rồi NẠP NGỮ CẢNH — hai việc, một hook, đúng thứ tự (pull TRƯỚC, đọc SAU).
#
# Việc 1 — đồng bộ 2 máy: fetch (trần ~8s); đứng sau origin + cây SẠCH + không diverge thì tự
# `pull --ff-only`; cây bẩn hoặc diverge thì chỉ NHẮC; commit chưa push cũng nhắc.
# Việc 2 — nạp ngữ cảnh vào đầu phiên:
#   · N câu chủ dự án vừa nhờ (nhật ký tự động)
#   · mục mới nhất của nhật ký phiên (do /kyuc:cuoi-ca viết)
#   · change OpenSpec đang mở + tiến độ task
#   · git log gần nhất
#
# Vì sao: ký ức của Claude KHÔNG đi theo máy, cũng không đi theo phiên. Không có hook này thì
# mỗi phiên mới lại hỏi lại thứ đã trả lời, đề xuất lại phương án đã bị loại.
#
# TẮT/BẬT theo repo qua `.claude/kyuc.json` (`git.tuPull`, `ngucanh.bat`). KHÔNG có file đó =
# repo chưa bật bộ này → im lặng thoát. LUÔN exit 0.
set -uo pipefail

ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || true)}"
[ -n "$ROOT" ] || exit 0
CFG="$ROOT/.claude/kyuc.json"
[ -f "$CFG" ] || exit 0
cd "$ROOT" 2>/dev/null || exit 0

# ---------- đọc cấu hình (thiếu/hỏng thì rơi về mặc định an toàn) ----------
read_cfg() { python3 -c "
import json,sys
try: c=json.load(open('$CFG'))
except Exception: c={}
cur=c
for k in '$1'.split('.'):
    cur=cur.get(k) if isinstance(cur,dict) else None
print('' if cur is None else ('1' if cur is True else ('0' if cur is False else cur)))
" 2>/dev/null; }

TU_PULL="$(read_cfg git.tuPull)"
NGU_CANH="$(read_cfg ngucanh.bat)"
SO_CAU="$(read_cfg ngucanh.soCau)"; [ -n "$SO_CAU" ] || SO_CAU=30
FILE_CH="$(read_cfg nhatky.cauHoi)"; [ -n "$FILE_CH" ] || FILE_CH="docs/nhatky/CAU_HOI.md"
FILE_PH="$(read_cfg nhatky.phien)";  [ -n "$FILE_PH" ] || FILE_PH="docs/nhatky/PHIEN.md"

SYNC_MSG=""
add_msg() { SYNC_MSG="${SYNC_MSG}$1"$'\n'; }

# ---------- VIỆC 1: đồng bộ ----------
if [ -d "$ROOT/.git" ] && [ "$TU_PULL" != "0" ]; then
  git fetch --quiet 2>/dev/null &
  fpid=$!; i=0
  while kill -0 "$fpid" 2>/dev/null && [ "$i" -lt 16 ]; do sleep 0.5; i=$((i + 1)); done
  if kill -0 "$fpid" 2>/dev/null; then
    kill "$fpid" 2>/dev/null; wait "$fpid" 2>/dev/null
    add_msg "⚠ git fetch quá 8s (mạng chậm/đứt?) — trạng thái so với origin dưới đây có thể CŨ."
  else
    wait "$fpid" 2>/dev/null || true
  fi

  upstream="$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)"
  if [ -n "$upstream" ]; then
    counts="$(git rev-list --left-right --count 'HEAD...@{upstream}' 2>/dev/null || true)"
    ahead="$(printf '%s' "$counts" | awk '{print $1}')"; behind="$(printf '%s' "$counts" | awk '{print $2}')"
    dirty="$(git status --porcelain 2>/dev/null | head -1)"
    if [ "${behind:-0}" -gt 0 ]; then
      if [ -z "$dirty" ] && [ "${ahead:-0}" -eq 0 ] && git pull --ff-only --quiet 2>/dev/null; then
        add_msg "✓ Đã tự \`git pull --ff-only\` $behind commit mới từ $upstream (cây sạch nên an toàn). FILE TRÊN ĐĨA VỪA ĐỔI — mọi thứ bạn nhớ về repo này có thể đã cũ."
      elif [ -n "$dirty" ]; then
        add_msg "⚠ Nhánh đứng SAU $upstream $behind commit nhưng cây làm việc CÒN THAY ĐỔI CHƯA COMMIT nên không tự pull. Xử lý chỗ dở (commit/stash) rồi \`git pull\` TRƯỚC khi làm tiếp."
      else
        add_msg "⚠ Nhánh đứng SAU $upstream $behind commit và đã DIVERGE (có commit local chưa push). Cần rebase/merge có chủ đích — hỏi chủ dự án trước khi tự quyết."
      fi
    fi
    [ "${ahead:-0}" -gt 0 ] && add_msg "⚠ Còn $ahead commit CHƯA PUSH từ phiên trước — \`git push\` sớm kẻo máy kia mở phiên sẽ không thấy."
  fi
fi

# ---------- VIỆC 2: nạp ngữ cảnh ----------
[ "$NGU_CANH" = "0" ] && { [ -n "$SYNC_MSG" ] && printf '%s' "$SYNC_MSG"; exit 0; }

python3 - "$ROOT" "$FILE_CH" "$FILE_PH" "$SO_CAU" "$SYNC_MSG" <<'PY' 2>/dev/null || { [ -n "$SYNC_MSG" ] && printf '%s' "$SYNC_MSG"; exit 0; }
import json, os, re, subprocess, sys

root, ch_rel, ph_rel, so_cau, sync_msg = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4] or 30), sys.argv[5]
parts = []

def sh(*cmd):
    try:
        return subprocess.run(cmd, cwd=root, capture_output=True, text=True, timeout=10).stdout.strip()
    except Exception:
        return ""

def read(path):
    try:
        return open(path, encoding="utf-8").read()
    except Exception:
        return ""

if sync_msg.strip():
    parts.append("## Đồng bộ 2 máy\n" + sync_msg.strip())

# 1. Chủ dự án đã nhờ gì gần đây — bỏ nhiễu máy tự sinh.
asks = []
for ln in read(os.path.join(root, ch_rel)).splitlines():
    m = re.match(r"^- \[(\d{2}:\d{2})\] (.+)$", ln)
    if not m:
        continue
    txt = m.group(2).strip()
    if txt.startswith(("<task-notification>", "<system-reminder>", "<local-command", "<command-name>")):
        continue
    asks.append(f"[{m.group(1)}] {txt[:200]}")
if asks:
    parts.append(
        f"## Chủ dự án đã nhờ gì gần đây ({so_cau} câu cuối, nguồn {ch_rel})\n" + "\n".join(asks[-so_cau:])
    )

# 2. Nhật ký phiên gần nhất — đang dở tới đâu, vì sao dừng, chờ ai quyết.
blocks = [b.strip() for b in re.split(r"(?m)^(?=## )", read(os.path.join(root, ph_rel))) if b.strip().startswith("## ")]
if blocks:
    parts.append(f"## Nhật ký phiên gần nhất (nguồn {ph_rel})\n" + blocks[-1][:1500])

# 3. OpenSpec — change đang mở + tiến độ.
os_dir = os.path.join(root, "openspec")
ch_dir = os.path.join(os_dir, "changes")
if os.path.isdir(ch_dir):
    rows = []
    for name in sorted(os.listdir(ch_dir)):
        d = os.path.join(ch_dir, name)
        if not os.path.isdir(d) or name == "archive" or name.startswith("."):
            continue
        arts = [a for a in ("proposal.md", "design.md", "specs", "tasks.md") if os.path.exists(os.path.join(d, a))]
        done = total = 0
        for ln in read(os.path.join(d, "tasks.md")).splitlines():
            s = ln.strip()
            if re.match(r"^[-*] \[[ xX]\]", s):
                total += 1
                if re.match(r"^[-*] \[[xX]\]", s):
                    done += 1
        prog = f"{done}/{total} task xong" if total else "chưa có task"
        rows.append(f"- `{name}` — {prog} — đã có: {', '.join(arts) or 'trống'}")
    if rows:
        parts.append(
            "## OpenSpec — change đang mở (nguồn openspec/changes/)\n" + "\n".join(rows)
            + "\n\nTiếp tục: `/opsx:apply <tên>` · xong hết task: `/opsx:archive <tên>`."
        )
    else:
        parts.append("## OpenSpec\nKhông có change nào đang mở. Việc mới đáng nhớ → `/opsx:propose <tên>`.")
elif not os.path.isdir(os_dir):
    parts.append("## OpenSpec\nRepo CHƯA init OpenSpec (thiếu `openspec/`). Chạy `/kyuc:khoi-tao`.")

# 4. Việc vừa làm.
log = sh("git", "log", "--oneline", "-8")
if log:
    branch = sh("git", "branch", "--show-current")
    parts.append(f"## Git — nhánh `{branch or '?'}`\n{log}")

if not parts:
    sys.exit(0)

ctx = (
    "# Ngữ cảnh tự nạp đầu phiên (plugin kyuc, hook dau-phien.sh)\n\n"
    "Đọc hết phần này TRƯỚC khi trả lời câu đầu tiên. Đây là việc đã diễn ra ở phiên trước "
    "và/hoặc Ở MÁY KIA — đừng hỏi lại thứ đã có câu trả lời ở đây, đừng đề xuất lại phương án "
    "đã bị loại. Phân vai: spec/quyết định → OpenSpec (/opsx:*) · TDD/debug/verify/review → "
    "superpowers · ký ức → kyuc. Chi tiết trong CLAUDE.md.\n\n" + "\n\n".join(parts)
)
print(json.dumps({
    "hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": ctx},
    "suppressOutput": True,
}))
PY
exit 0
