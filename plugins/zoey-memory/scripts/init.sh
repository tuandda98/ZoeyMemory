#!/usr/bin/env bash
# Enable ZoeyMemory in a repo: openspec init + .claude/zoey-memory.json + docs/memory/ + CLAUDE.md block.
# IDEMPOTENT: re-running never overwrites what already exists. Does not commit - Claude/the user does that.
#
# Usage: bash init.sh [repo path]   (default: $CLAUDE_PROJECT_DIR, else git toplevel, else pwd)
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TPL="$HERE/templates"
ROOT="${1:-${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}}"
ROOT="$(cd "$ROOT" 2>/dev/null && pwd)" || { echo "ERROR: cannot enter directory: $1"; exit 1; }
cd "$ROOT" || exit 1

ok()   { printf 'OK    %s\n' "$*"; }
warn() { printf 'WARN  %s\n' "$*"; }
skip() { printf 'skip  %s\n' "$*"; }

echo "# ZoeyMemory init - $ROOT"
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

# 3. openspec init (non-interactive, English, Claude Code commands only)
if [ -d openspec ]; then
  skip "openspec/ already present"
elif command -v openspec >/dev/null 2>&1; then
  if openspec init --tools claude --language en --no-animation . >/dev/null 2>&1; then
    ok "openspec init (tools=claude, language=en)"
  else
    warn "openspec init failed - run manually: openspec init --tools claude --language en"
  fi
fi

# 4. .claude/zoey-memory.json (strip `_` doc keys, name = folder name)
mkdir -p .claude
if [ -f .claude/zoey-memory.json ]; then
  skip ".claude/zoey-memory.json already present"
else
  python3 - "$TPL/zoey-memory.json" ".claude/zoey-memory.json" "$(basename "$ROOT")" <<'PY' && ok ".claude/zoey-memory.json" || warn "could not create .claude/zoey-memory.json"
import json, sys
src, dst, name = sys.argv[1:4]
c = json.load(open(src, encoding="utf-8"))
def strip(o):
    if isinstance(o, dict):
        return {k: strip(v) for k, v in o.items() if not k.startswith("_")}
    if isinstance(o, list):
        return [strip(v) for v in o]
    return o
c = strip(c)
c["name"] = name
with open(dst, "w", encoding="utf-8") as f:
    json.dump(c, f, ensure_ascii=False, indent=2)
    f.write("\n")
PY
fi

# 5. docs/memory/
cfg_get() { python3 -c "
import json
try: c=json.load(open('.claude/zoey-memory.json'))
except Exception: c={}
print(((c.get('journal') or {}).get('$1')) or '$2')" 2>/dev/null; }
PROMPTS="$(cfg_get prompts docs/memory/PROMPTS.md)"
SESSIONS="$(cfg_get sessions docs/memory/SESSIONS.md)"
mkdir -p "$(dirname "$PROMPTS")" "$(dirname "$SESSIONS")"
if [ -f "$PROMPTS" ]; then skip "$PROMPTS already present"; else
  cat > "$PROMPTS" <<'EOF'
# Prompt journal (automatic)

Written by the ZoeyMemory hook `log-prompt.sh`: a marker per session plus every prompt the user sends.
This file is COMMITTED so the other machine can see what this one was asked to do.

Do not hand-edit the automatic lines. To record the OUTCOME of a task, add a line starting with `> `
right under the matching prompt. The REASONING behind a decision belongs in OpenSpec (`openspec/changes/<name>/`).
EOF
  ok "$PROMPTS"
fi
if [ -f "$SESSIONS" ]; then skip "$SESSIONS already present"; else
  cat > "$SESSIONS" <<'EOF'
# Session journal

Every time you leave a machine (`/zoey-memory:handoff`) append ONE new entry at the end, using this shape:

## YYYY-MM-DD HH:MM - branch `main` - machine <hostname>
- In progress: ...
- Why we stopped: ...
- Waiting on whom for what: ...
- The other machine needs to know (things outside git): ...

The `session-start.sh` hook loads the LATEST entry into the next session. Do not repeat `git log` -
commits answer "what changed", this entry answers "why, and what comes next".
EOF
  ok "$SESSIONS"
fi

# 6. CLAUDE.md - append the workflow block if missing
if [ -f CLAUDE.md ] && grep -q '<!-- zoey-memory:start -->' CLAUDE.md; then
  skip "CLAUDE.md already has the ZoeyMemory block"
else
  { [ -s CLAUDE.md ] && printf '\n'; cat "$TPL/CLAUDE.md"; } >> CLAUDE.md
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
