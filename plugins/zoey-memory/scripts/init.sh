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
#               An unknown code ABORTS before touching anything (exit 1) - it never falls back.
#   repo path   default: $CLAUDE_PROJECT_DIR, else cwd - always resolved to the git top level, so
#               running inside a subdirectory of a repo enables the repo, never a nested one.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TPL="$HERE/templates"
I18N="$TPL/i18n"
ZOEY="$HERE/lib/zoey.py"
. "$HERE/lib/common.sh"

ok()   { printf 'OK    %s\n' "$*"; }
warn() { printf 'WARN  %s\n' "$*"; }
skip() { printf 'skip  %s\n' "$*"; }
die()  { printf 'ERROR %s\n' "$*"; exit 1; }

LANG_REQ=""
ROOT_ARG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --language|-l) [ $# -ge 2 ] || die "--language needs a value (e.g. --language vi)"; LANG_REQ="$2"; shift 2 ;;
    --language=*)  LANG_REQ="${1#*=}"; shift ;;
    -h|--help)     sed -n '2,15p' "${BASH_SOURCE[0]}"; exit 0 ;;
    -*)            die "unknown option: $1" ;;
    *)             ROOT_ARG="$1"; shift ;;
  esac
done

if [ -n "$ROOT_ARG" ]; then
  [ -d "$ROOT_ARG" ] || die "not a directory: $ROOT_ARG"
  ROOT="$(zoey_resolve_root "$ROOT_ARG")"
  given="$(cd "$ROOT_ARG" && pwd)"
  [ "$ROOT" != "$given" ] && echo "note  $given is inside the repo at $ROOT - enabling the repo root"
else
  ROOT="$(zoey_resolve_root)"
fi
cd "$ROOT" || die "cannot enter $ROOT"
CFG="$ROOT/.claude/zoey-memory.json"

# Language: explicit flag > existing config > en. Unknown code -> abort, nothing written.
if [ -f "$CFG" ]; then
  python3 "$ZOEY" validate "$CFG" 2>/dev/null || die "$CFG is not valid JSON - fix it (or delete it to start over) before re-running"
  LANG_CODE="$(python3 "$ZOEY" lang "$CFG" "$I18N" "$LANG_REQ" 2>&1)" || die "language: $LANG_CODE"
else
  LANG_CODE="$(python3 "$ZOEY" lang - "$I18N" "$LANG_REQ" 2>&1)" || die "language: $LANG_CODE"
fi

echo "# ZoeyMemory init - $ROOT (language: $LANG_CODE)"
echo

# 1. git
if zoey_in_git "$ROOT"; then skip "git already present"; else git init -q && ok "git init"; fi

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
  skip "openspec/ already present (its language is not changed - edit openspec/config.yaml if needed)"
elif command -v openspec >/dev/null 2>&1; then
  if openspec init --tools claude --language "$LANG_CODE" --no-animation . >/dev/null 2>&1; then
    ok "openspec init (tools=claude, language=$LANG_CODE)"
  else
    warn "openspec init failed - run manually: openspec init --tools claude --language $LANG_CODE"
  fi
fi

# 4. .claude/zoey-memory.json
mkdir -p .claude
if [ -f "$CFG" ]; then
  cur="$(python3 "$ZOEY" get "$CFG" language "" 2>/dev/null)"
  if [ "$cur" != "$LANG_CODE" ]; then
    python3 "$ZOEY" set-lang "$CFG" "$LANG_CODE" && ok ".claude/zoey-memory.json language: ${cur:-(unset)} -> $LANG_CODE" || warn "could not update language in $CFG"
  else
    skip ".claude/zoey-memory.json already present"
  fi
else
  python3 "$ZOEY" init-config "$TPL/zoey-memory.json" "$CFG" "$(basename "$ROOT")" "$LANG_CODE" && ok ".claude/zoey-memory.json" || warn "could not create $CFG"
fi

# 5. docs/memory/ - headers come from i18n so hooks and init agree; never write an empty file
PROMPTS="$(python3 "$ZOEY" get "$CFG" journal.prompts docs/memory/PROMPTS.md)"
SESSIONS="$(python3 "$ZOEY" get "$CFG" journal.sessions docs/memory/SESSIONS.md)"
write_journal() {  # <path> <i18n key>
  local content
  if [ -s "$1" ]; then skip "$1 already present"; return; fi
  content="$(python3 "$ZOEY" i18n "$I18N" "$LANG_CODE" "$2" 2>/dev/null)"
  if [ -n "$content" ]; then
    mkdir -p "$(dirname "$1")" && printf '%s' "$content" > "$1" && ok "$1"
  else
    warn "$1 not written: i18n key '$2' missing for '$LANG_CODE'"
  fi
}
write_journal "$PROMPTS" prompts_header
write_journal "$SESSIONS" sessions_header

# 6. CLAUDE.md - plugin-owned block between markers: append if missing, refresh if different
BLOCK_TPL="$TPL/CLAUDE.$LANG_CODE.md"; [ -f "$BLOCK_TPL" ] || BLOCK_TPL="$TPL/CLAUDE.en.md"
status="$(python3 "$ZOEY" block CLAUDE.md "$BLOCK_TPL" 2>/dev/null)"
case "$status" in
  added)      ok "CLAUDE.md += ZoeyMemory block (ZoeyMemory / OpenSpec / superpowers division of labor)" ;;
  refreshed)  ok "CLAUDE.md block refreshed from template" ;;
  up-to-date) skip "CLAUDE.md block already up to date" ;;
  *)          warn "CLAUDE.md has a broken ZoeyMemory block (one marker without the other) - fix the <!-- zoey-memory:start --> / <!-- zoey-memory:end --> markers by hand, then re-run" ;;
esac

# 7. .gitignore
touch .gitignore
if grep -qx '.claude/settings.local.json' .gitignore; then skip ".gitignore already has settings.local.json"; else
  printf '.claude/settings.local.json\n' >> .gitignore; ok ".gitignore += .claude/settings.local.json"
fi

# 8. superpowers installed and enabled?
sp="$(claude plugin list --json 2>/dev/null | python3 -c '
import json,sys
try: items=json.load(sys.stdin)
except Exception: items=[]
for p in items if isinstance(items,list) else []:
    if str(p.get("id","")).startswith("superpowers@"):
        print("%s\t%s" % (p.get("version","?"), "enabled" if p.get("enabled") else "disabled")); break
' 2>/dev/null)"
case "$sp" in
  *enabled)  ok "superpowers ${sp%%	*} enabled" ;;
  *disabled) warn "superpowers ${sp%%	*} installed but DISABLED (claude plugin enable superpowers@superpowers-marketplace)" ;;
  *)         warn "superpowers NOT installed. Install: claude plugin marketplace add obra/superpowers-marketplace && claude plugin install superpowers@superpowers-marketplace" ;;
esac

echo
echo "Done. Hooks take effect from the next session (or run /reload-plugins). Commit the files above so the other machine gets them."
exit 0
