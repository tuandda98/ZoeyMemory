#!/usr/bin/env bash
# Enable ZoeyMemory in a repo: openspec init + .claude/zoey-memory.json + docs/memory/ + CLAUDE.md block.
# IDEMPOTENT: re-running never overwrites user files. The CLAUDE.md block between the
# `<!-- zoey-memory:start/end -->` markers is plugin-owned and IS refreshed from the template.
# Does not commit - Claude/the user does that.
#
# Usage: bash init.sh [--language <code>] [repo path]
#   --language  en (default) | vi | any code with a templates/i18n/<code>.json file.
#               Sets `language` in the config, picks templates/CLAUDE.<code>.md, and is passed to
#               `openspec init --language`. Re-run with a different code to switch languages.
#   repo path   default: $CLAUDE_PROJECT_DIR, else git toplevel, else pwd
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TPL="$HERE/templates"

LANG_REQ=""
ROOT_ARG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --language|-l) LANG_REQ="${2:-}"; shift 2 ;;
    --language=*)  LANG_REQ="${1#*=}"; shift ;;
    *)             ROOT_ARG="$1"; shift ;;
  esac
done

ROOT="${ROOT_ARG:-${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}}"
ROOT="$(cd "$ROOT" 2>/dev/null && pwd)" || { echo "ERROR: cannot enter directory: $ROOT_ARG"; exit 1; }
cd "$ROOT" || exit 1

ok()   { printf 'OK    %s\n' "$*"; }
warn() { printf 'WARN  %s\n' "$*"; }
skip() { printf 'skip  %s\n' "$*"; }

cfg_get() { python3 -c "
import json,sys
try: c=json.load(open('.claude/zoey-memory.json'))
except Exception: c={}
cur=c
for k in '$1'.split('.'):
    cur=cur.get(k) if isinstance(cur,dict) else None
print(cur if cur not in (None,'') else '$2')" 2>/dev/null; }

i18n_get() { python3 -c "
import json,sys
def load(p):
    try: return json.load(open(p,encoding='utf-8'))
    except Exception: return {}
t=load('$TPL/i18n/en.json'); t.update(load('$TPL/i18n/$1.json'))
sys.stdout.write(t.get('$2',''))" 2>/dev/null; }

# Resolve language: explicit flag > existing config > en. Must have an i18n file.
if [ -n "$LANG_REQ" ]; then LANG_CODE="$LANG_REQ"
elif [ -f .claude/zoey-memory.json ]; then LANG_CODE="$(cfg_get language en)"
else LANG_CODE="en"; fi
if [ ! -f "$TPL/i18n/$LANG_CODE.json" ]; then
  warn "no templates/i18n/$LANG_CODE.json - falling back to en (add that file to support '$LANG_CODE')"
  LANG_CODE="en"
fi

echo "# ZoeyMemory init - $ROOT (language: $LANG_CODE)"
echo

# 1. git
if [ -d .git ]; then skip "git already present"; else git init -q && ok "git init"; fi

# 2. openspec CLI
if command -v openspec >/dev/null 2>&1; then
  ok "openspec CLI $(openspec --version 2>/dev/null)"
elif command -v npm >/dev/null 2>&1; then
  echo "..    installing openspec CLI"
  if npm install -g @fission-ai/openspec@latest >/dev/null 2>&1; then
    ok "openspec CLI $(openspec --version 2>/dev/null)"
  else
    warn "could not install openspec CLI - install manually: npm i -g @fission-ai/openspec@latest"
  fi
else
  warn "npm missing, cannot install openspec CLI (needs Node 20.19+)"
fi

# 3. openspec init (non-interactive, Claude Code commands only, same language)
if [ -d openspec ]; then
  skip "openspec/ already present (language there is not changed - edit openspec/config.yaml if needed)"
elif command -v openspec >/dev/null 2>&1; then
  if openspec init --tools claude --language "$LANG_CODE" --no-animation . >/dev/null 2>&1; then
    ok "openspec init (tools=claude, language=$LANG_CODE)"
  else
    warn "openspec init failed - run manually: openspec init --tools claude --language $LANG_CODE"
  fi
fi

# 4. .claude/zoey-memory.json (strip `_` doc keys, name = folder name, language = chosen)
mkdir -p .claude
if [ -f .claude/zoey-memory.json ]; then
  cur="$(cfg_get language en)"
  if [ "$cur" != "$LANG_CODE" ]; then
    python3 - ".claude/zoey-memory.json" "$LANG_CODE" <<'PY' && ok ".claude/zoey-memory.json language: $cur -> $LANG_CODE" || warn "could not update language in config"
import json, sys
p, lang = sys.argv[1:3]
c = json.load(open(p, encoding="utf-8")); c["language"] = lang
with open(p, "w", encoding="utf-8") as f:
    json.dump(c, f, ensure_ascii=False, indent=2); f.write("\n")
PY
  else
    skip ".claude/zoey-memory.json already present"
  fi
else
  python3 - "$TPL/zoey-memory.json" ".claude/zoey-memory.json" "$(basename "$ROOT")" "$LANG_CODE" <<'PY' && ok ".claude/zoey-memory.json" || warn "could not create .claude/zoey-memory.json"
import json, sys
src, dst, name, lang = sys.argv[1:5]
c = json.load(open(src, encoding="utf-8"))
def strip(o):
    if isinstance(o, dict):
        return {k: strip(v) for k, v in o.items() if not k.startswith("_")}
    if isinstance(o, list):
        return [strip(v) for v in o]
    return o
c = strip(c)
c["name"] = name
c["language"] = lang
with open(dst, "w", encoding="utf-8") as f:
    json.dump(c, f, ensure_ascii=False, indent=2)
    f.write("\n")
PY
fi

# 5. docs/memory/ (headers come from i18n so hooks and init agree)
PROMPTS="$(cfg_get journal.prompts docs/memory/PROMPTS.md)"
SESSIONS="$(cfg_get journal.sessions docs/memory/SESSIONS.md)"
mkdir -p "$(dirname "$PROMPTS")" "$(dirname "$SESSIONS")"
if [ -f "$PROMPTS" ]; then skip "$PROMPTS already present"; else
  i18n_get "$LANG_CODE" prompts_header > "$PROMPTS" && ok "$PROMPTS"
fi
if [ -f "$SESSIONS" ]; then skip "$SESSIONS already present"; else
  i18n_get "$LANG_CODE" sessions_header > "$SESSIONS" && ok "$SESSIONS"
fi

# 6. CLAUDE.md - plugin-owned block between markers: append if missing, refresh if different
BLOCK_TPL="$TPL/CLAUDE.$LANG_CODE.md"; [ -f "$BLOCK_TPL" ] || BLOCK_TPL="$TPL/CLAUDE.en.md"
touch CLAUDE.md
if grep -q '<!-- zoey-memory:start -->' CLAUDE.md; then
  python3 - CLAUDE.md "$BLOCK_TPL" <<'PY'
import re, sys
path, tpl = sys.argv[1:3]
src = open(path, encoding="utf-8").read()
new = open(tpl, encoding="utf-8").read().strip()
pat = re.compile(r"<!-- zoey-memory:start -->.*?<!-- zoey-memory:end -->", re.S)
m = pat.search(src)
if m and m.group(0).strip() == new:
    print("skip  CLAUDE.md block already up to date")
else:
    open(path, "w", encoding="utf-8").write(pat.sub(lambda _: new, src, count=1))
    print("OK    CLAUDE.md block refreshed from template")
PY
else
  { [ -s CLAUDE.md ] && printf '\n'; cat "$BLOCK_TPL"; } >> CLAUDE.md
  ok "CLAUDE.md += ZoeyMemory block (ZoeyMemory / OpenSpec / superpowers division of labor)"
fi

# 7. .gitignore
touch .gitignore
if grep -qx '.claude/settings.local.json' .gitignore; then skip ".gitignore already has settings.local.json"; else
  printf '.claude/settings.local.json\n' >> .gitignore; ok ".gitignore += .claude/settings.local.json"
fi

# 8. superpowers installed?
if claude plugin list 2>/dev/null | grep -q 'superpowers@'; then
  ok "superpowers installed"
else
  warn "superpowers NOT installed. Install: claude plugin marketplace add obra/superpowers-marketplace && claude plugin install superpowers@superpowers-marketplace"
fi

echo
echo "Done. Hooks take effect from the next session (or run /reload-plugins). Commit the files above so the other machine gets them."
exit 0
