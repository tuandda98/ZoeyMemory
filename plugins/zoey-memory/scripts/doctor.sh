#!/usr/bin/env bash
# Health check for a repo that uses ZoeyMemory + OpenSpec + superpowers.
# Detects drift after any of the three tools is updated: missing files, renamed skills, stale
# CLAUDE.md block, language mismatch, generated OpenSpec files out of date.
# READ-ONLY and OFFLINE: touches nothing, makes no network calls. Exit 0 always; the last line says
# how many WARN lines there are.
#
# Usage: bash doctor.sh [repo path]
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TPL="$HERE/templates"
I18N="$TPL/i18n"
ZOEY="$HERE/lib/zoey.py"
. "$HERE/lib/common.sh"

ROOT_ARG="${1:-}"
if [ -n "$ROOT_ARG" ]; then
  [ -d "$ROOT_ARG" ] || { echo "ERROR cannot enter directory: $ROOT_ARG"; exit 1; }
  ROOT="$(zoey_resolve_root "$ROOT_ARG")"
else
  ROOT="$(zoey_resolve_root)"
fi
cd "$ROOT" || { echo "ERROR cannot enter directory: $ROOT"; exit 1; }
CFG="$ROOT/.claude/zoey-memory.json"

WARNS=0
ok()   { printf 'OK    %s\n' "$*"; }
warn() { printf 'WARN  %s\n' "$*"; WARNS=$((WARNS + 1)); }
info() { printf '..    %s\n' "$*"; }

echo "# ZoeyMemory doctor - $ROOT"
echo

# ---- 1. ZoeyMemory config ----
echo "## ZoeyMemory"
LANG_CODE=en
# Journal paths exactly as the hooks resolve them - reused by the git and CLAUDE.md checks.
J_PATHS="$(python3 "$ZOEY" paths "$CFG" 2>/dev/null)"
J_PROMPTS="$(printf '%s\n' "$J_PATHS" | sed -n 1p)"; J_SESSIONS="$(printf '%s\n' "$J_PATHS" | sed -n 2p)"
if [ ! -f "$CFG" ]; then
  warn "no .claude/zoey-memory.json - ZoeyMemory is not enabled here. Run /zoey-memory:init"
elif ! reason="$(python3 "$ZOEY" validate "$CFG" 2>&1)"; then
  warn ".claude/zoey-memory.json is invalid ($reason) - hooks skip journaling and sync and only print a warning"
else
  ok ".claude/zoey-memory.json valid"
  if lang="$(python3 "$ZOEY" lang "$CFG" "$I18N" 2>&1)"; then
    LANG_CODE="$lang"; ok "language '$LANG_CODE' has templates/i18n/$LANG_CODE.json"
  else
    warn "language: $lang - hooks fall back to en until fixed"
  fi
  for key in journal.prompts journal.sessions; do
    if [ "$key" = journal.prompts ]; then f="$J_PROMPTS"; else f="$J_SESSIONS"; fi
    if [ -s "$f" ]; then ok "$key -> $f"
    elif [ -f "$f" ]; then warn "$key -> $f is EMPTY (re-run /zoey-memory:init to write the header)"
    else warn "$key -> $f missing (re-run /zoey-memory:init; the prompt journal is also created on first write)"; fi
  done
  tz="$(python3 "$ZOEY" get "$CFG" timezone "" 2>/dev/null)"
  if [ -n "$tz" ]; then
    if [ -f "/usr/share/zoneinfo/$tz" ]; then ok "timezone $tz (journal timestamps)"
    else warn "timezone '$tz' is not a known zone (no /usr/share/zoneinfo/$tz) - journal times silently fall back to UTC"; fi
  fi
  [ -f .claude/flow.json ] && warn ".claude/flow.json present - the old 'flow' plugin also journals prompts; disable one of them to avoid double logging"
fi

# ---- 2. git ----
echo; echo "## git"
if zoey_in_git "$ROOT"; then
  up="$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)"
  [ -n "$up" ] && ok "upstream $up (two-machine sync can work)" || warn "no upstream for the current branch - the session-start hook cannot auto-pull or warn about unpushed commits (git push -u origin <branch>)"
  for f in .claude/zoey-memory.json "$J_PROMPTS" "$J_SESSIONS" CLAUDE.md openspec; do
    [ -e "$f" ] || continue
    git check-ignore -q "$f" 2>/dev/null && warn "$f is git-ignored - it will NOT reach the other machine" || true
  done
else
  warn "not a git repository - nothing travels to the other machine"
fi

# ---- 3. OpenSpec ----
echo; echo "## OpenSpec"
if command -v openspec >/dev/null 2>&1; then
  ok "openspec CLI $(openspec --version 2>/dev/null) (update with /zoey-memory:update)"
else
  warn "openspec CLI not installed - /opsx:* commands will fail (npm i -g @fission-ai/openspec@latest)"
fi
if [ -d openspec ]; then
  ok "openspec/ present"
  [ -d openspec/changes ] || warn "openspec/changes/ missing - the session-start hook cannot list open changes"
  missing=""
  for c in explore propose apply archive; do
    [ -f ".claude/commands/opsx/$c.md" ] || missing="$missing $c"
  done
  if [ -z "$missing" ]; then ok "/opsx:explore propose apply archive present in .claude/commands/opsx/"
  else warn "missing generated commands:$missing - run: openspec update  (if the CLI changed its layout, re-check the CLAUDE.md wording too)"; fi
  if [ -f openspec/config.yaml ]; then
    os_lang="$(grep -m1 -E '^[[:space:]]*Language:' openspec/config.yaml | sed -E 's/.*Language:[[:space:]]*//' | tr -d '[:space:]' || true)"
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
sp="$(claude plugin list --json 2>/dev/null | python3 -c '
import json,sys
try: items=json.load(sys.stdin)
except Exception: items=[]
for p in items if isinstance(items,list) else []:
    if str(p.get("id","")).startswith("superpowers@"):
        print("%s\t%s\t%s" % (p.get("version","?"), "enabled" if p.get("enabled") else "disabled", p.get("installPath",""))); break
' 2>/dev/null)"
if [ -z "$sp" ]; then
  warn "superpowers not installed - TDD/debugging/verification/review skills unavailable (claude plugin marketplace add obra/superpowers-marketplace && claude plugin install superpowers@superpowers-marketplace)"
else
  sp_ver="$(printf '%s' "$sp" | cut -f1)"; sp_state="$(printf '%s' "$sp" | cut -f2)"; sp_path="$(printf '%s' "$sp" | cut -f3)"
  [ "$sp_state" = "enabled" ] && ok "superpowers $sp_ver enabled" || warn "superpowers $sp_ver installed but DISABLED (claude plugin enable superpowers@superpowers-marketplace)"
  if [ -d "$sp_path/skills" ]; then
    # Skill names the CLAUDE.md block refers to. If superpowers renames one, this catches it.
    missing=""
    for s in brainstorming writing-plans executing-plans test-driven-development systematic-debugging verification-before-completion requesting-code-review; do
      [ -d "$sp_path/skills/$s" ] || missing="$missing $s"
    done
    if [ -z "$missing" ]; then ok "all skills referenced by the CLAUDE.md block exist in superpowers $sp_ver"
    else warn "superpowers $sp_ver no longer has:$missing - update templates/CLAUDE.<lang>.md and this list in doctor.sh, then re-run init.sh to refresh the block"; fi
  else
    warn "cannot find superpowers skills at $sp_path/skills - reinstall superpowers"
  fi
fi

# ---- 5. CLAUDE.md block ----
echo; echo "## CLAUDE.md"
BLOCK_TPL="$TPL/CLAUDE.$LANG_CODE.md"; [ -f "$BLOCK_TPL" ] || BLOCK_TPL="$TPL/CLAUDE.en.md"
if [ ! -f CLAUDE.md ]; then
  warn "no CLAUDE.md - the division-of-labor rules are not loaded (run /zoey-memory:init)"
else
  case "$(python3 "$ZOEY" block-check CLAUDE.md "$BLOCK_TPL" "$CFG" 2>/dev/null)" in
    ok)      ok "CLAUDE.md block matches the template for '$LANG_CODE' (journal paths: $J_PROMPTS, $J_SESSIONS)" ;;
    differs) warn "CLAUDE.md block differs from the template (plugin updated, language changed, or journal paths changed) - run: bash <plugin>/scripts/init.sh to refresh it" ;;
    missing) warn "CLAUDE.md has no ZoeyMemory block - run /zoey-memory:init" ;;
    *)       warn "CLAUDE.md has a broken ZoeyMemory block (one marker without the other) - fix the markers by hand" ;;
  esac
fi

echo
if [ "$WARNS" -eq 0 ]; then echo "Healthy: 0 warnings."; else echo "$WARNS warning(s) above."; fi
exit 0
