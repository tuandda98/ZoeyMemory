#!/usr/bin/env bash
# Health check for a repo that uses ZoeyMemory + OpenSpec + superpowers.
# Detects drift after any of the three tools is updated: missing files, renamed skills, stale
# CLAUDE.md block, language mismatch, generated OpenSpec files out of date. Read-only. Exit 0 always;
# the last line says how many WARN lines there are.
#
# Usage: bash doctor.sh [repo path]
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TPL="$HERE/templates"
ROOT="${1:-${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}}"
ROOT="$(cd "$ROOT" 2>/dev/null && pwd)" || { echo "ERROR: cannot enter directory: $1"; exit 1; }
cd "$ROOT" || exit 1

WARNS=0
ok()   { printf 'OK    %s\n' "$*"; }
warn() { printf 'WARN  %s\n' "$*"; WARNS=$((WARNS + 1)); }
info() { printf '..    %s\n' "$*"; }

cfg_get() { python3 -c "
import json,sys
try: c=json.load(open('.claude/zoey-memory.json'))
except Exception: c={}
cur=c
for k in '$1'.split('.'):
    cur=cur.get(k) if isinstance(cur,dict) else None
print(cur if cur not in (None,'') else '$2')" 2>/dev/null; }

echo "# ZoeyMemory doctor - $ROOT"
echo

# ---- 1. ZoeyMemory config ----
echo "## ZoeyMemory"
if [ ! -f .claude/zoey-memory.json ]; then
  warn "no .claude/zoey-memory.json - ZoeyMemory is not enabled here. Run /zoey-memory:init"
  LANG_CODE=en
elif ! python3 -m json.tool .claude/zoey-memory.json >/dev/null 2>&1; then
  warn ".claude/zoey-memory.json is not valid JSON - every hook is silently skipping this repo"
  LANG_CODE=en
else
  ok ".claude/zoey-memory.json valid"
  LANG_CODE="$(cfg_get language en)"
  if [ -f "$TPL/i18n/$LANG_CODE.json" ]; then ok "language '$LANG_CODE' has templates/i18n/$LANG_CODE.json"
  else warn "language '$LANG_CODE' has no templates/i18n/$LANG_CODE.json - hooks fall back to en"; fi
  for key in journal.prompts journal.sessions; do
    f="$(cfg_get $key '')"
    [ -n "$f" ] && [ -f "$f" ] && ok "$key -> $f" || warn "$key -> '${f:-?}' missing (init creates it; the hook also creates the prompt journal on first write)"
  done
  if [ -f .claude/flow.json ]; then
    warn ".claude/flow.json present - the old 'flow' plugin also journals prompts; disable one of them to avoid double logging"
  fi
fi

# ---- 2. git ----
echo; echo "## git"
if [ -d .git ]; then
  up="$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)"
  [ -n "$up" ] && ok "upstream $up (two-machine sync can work)" || warn "no upstream for the current branch - session-start.sh cannot auto-pull or warn about unpushed commits (git push -u origin <branch>)"
  for f in .claude/zoey-memory.json docs/memory CLAUDE.md openspec; do
    [ -e "$f" ] || continue
    git check-ignore -q "$f" 2>/dev/null && warn "$f is git-ignored - it will NOT reach the other machine" || true
  done
else
  warn "not a git repository - nothing travels to the other machine"
fi

# ---- 3. OpenSpec ----
echo; echo "## OpenSpec"
if command -v openspec >/dev/null 2>&1; then
  ok "openspec CLI $(openspec --version 2>/dev/null)"
  latest="$(npm view @fission-ai/openspec version 2>/dev/null || true)"
  if [ -n "$latest" ] && [ "$latest" != "$(openspec --version 2>/dev/null)" ]; then
    info "newer openspec available: $latest (bash <plugin>/scripts/update.sh)"
  fi
else
  warn "openspec CLI not installed - /opsx:* commands will fail (npm i -g @fission-ai/openspec@latest)"
fi
if [ -d openspec ]; then
  ok "openspec/ present"
  [ -d openspec/changes ] || warn "openspec/changes/ missing - session-start.sh cannot list open changes"
  missing=""
  for c in explore propose apply archive; do
    [ -f ".claude/commands/opsx/$c.md" ] || missing="$missing $c"
  done
  if [ -z "$missing" ]; then ok "/opsx:explore propose apply archive present in .claude/commands/opsx/"
  else warn "missing generated commands:$missing - run: openspec update  (the CLI layout may have changed; then re-check CLAUDE.md wording)"; fi
  if [ -f openspec/config.yaml ]; then
    os_lang="$(grep -m1 -E '^\s*Language:' openspec/config.yaml | sed -E 's/.*Language:\s*//' | tr -d ' ' || true)"
    if [ -n "$os_lang" ] && [ "$os_lang" != "$LANG_CODE" ]; then
      warn "openspec/config.yaml says Language: $os_lang but ZoeyMemory language is $LANG_CODE - edit the context block in openspec/config.yaml"
    else
      ok "openspec language matches ($LANG_CODE)"
    fi
  fi
else
  warn "openspec/ missing - run /zoey-memory:init (or openspec init --tools claude)"
fi

# ---- 4. superpowers ----
echo; echo "## superpowers"
sp_line="$(claude plugin list 2>/dev/null | grep -A3 'superpowers@' || true)"
if [ -z "$sp_line" ]; then
  warn "superpowers not installed - TDD/debugging/verification/review skills unavailable (claude plugin marketplace add obra/superpowers-marketplace && claude plugin install superpowers@superpowers-marketplace)"
else
  ver="$(printf '%s' "$sp_line" | grep -oE 'Version: [^ ]+' | head -1 | cut -d' ' -f2)"
  printf '%s' "$sp_line" | grep -q 'enabled' && ok "superpowers $ver enabled" || warn "superpowers $ver installed but DISABLED (claude plugin enable superpowers@superpowers-marketplace)"
  skills_dir="$(ls -d ~/.claude/plugins/cache/superpowers-marketplace/superpowers/*/skills 2>/dev/null | sort -V | tail -1)"
  if [ -n "$skills_dir" ]; then
    # Skill names the CLAUDE.md block refers to. If superpowers renames one, this catches it.
    missing=""
    for s in brainstorming writing-plans executing-plans test-driven-development systematic-debugging verification-before-completion requesting-code-review; do
      [ -d "$skills_dir/$s" ] || missing="$missing $s"
    done
    if [ -z "$missing" ]; then ok "all skills referenced by the CLAUDE.md block exist in $(basename "$(dirname "$skills_dir")")"
    else warn "superpowers no longer has:$missing - update templates/CLAUDE.<lang>.md and this list in doctor.sh, then re-run init.sh to refresh the block"; fi
  fi
fi

# ---- 5. CLAUDE.md block ----
echo; echo "## CLAUDE.md"
if [ ! -f CLAUDE.md ]; then
  warn "no CLAUDE.md - the division-of-labor rules are not loaded (run /zoey-memory:init)"
elif ! grep -q '<!-- zoey-memory:start -->' CLAUDE.md; then
  warn "CLAUDE.md has no ZoeyMemory block - run /zoey-memory:init"
else
  BLOCK_TPL="$TPL/CLAUDE.$LANG_CODE.md"; [ -f "$BLOCK_TPL" ] || BLOCK_TPL="$TPL/CLAUDE.en.md"
  python3 - CLAUDE.md "$BLOCK_TPL" <<'PY' && :
import re, sys
src = open(sys.argv[1], encoding="utf-8").read()
new = open(sys.argv[2], encoding="utf-8").read().strip()
m = re.search(r"<!-- zoey-memory:start -->.*?<!-- zoey-memory:end -->", src, re.S)
if m and m.group(0).strip() == new:
    print("OK    CLAUDE.md block matches the template for this language")
else:
    print("WARN  CLAUDE.md block differs from the template (plugin updated, or language changed) - run: bash <plugin>/scripts/init.sh to refresh it")
    sys.exit(3)
PY
  [ $? -eq 3 ] && WARNS=$((WARNS + 1))
fi

echo
if [ "$WARNS" -eq 0 ]; then echo "Healthy: 0 warnings."; else echo "$WARNS warning(s) above."; fi
exit 0
