#!/usr/bin/env bash
# SessionStart: SYNC, then MARK, then LOAD CONTEXT - one hook, in that order.
#
# 1. Two-machine sync (bash): fetch with an 8 s limit; if behind origin AND the tree is clean AND
#    not ahead, `pull --ff-only` with a 20 s limit. Anything else only WARNS. Every outcome is
#    emitted as a TAB-separated event (a TAB cannot appear in a git ref name).
# 2. Session marker: the "new session" line goes into docs/memory/PROMPTS.md only now, after the
#    pull, so the tracked journal is never what makes the tree dirty at pull time.
# 3. Context (python, lib/session_start.py): recent prompts, latest session note, open OpenSpec
#    changes with progress, git log - rendered in the configured language.
#
# Why: Claude's memory does not travel across machines or sessions. Without this hook every new
# session re-asks what was already answered and re-proposes options already rejected.
#
# No `.claude/zoey-memory.json` at the repo root = ZoeyMemory not enabled -> exit silently.
# Invalid config -> no sync, no marker, and a warning in the loaded context. ALWAYS exit 0.
set -uo pipefail

PLUGIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$PLUGIN/lib/common.sh"

ROOT="$(zoey_resolve_root)"
[ -n "$ROOT" ] || exit 0
CFG="$ROOT/.claude/zoey-memory.json"
[ -f "$CFG" ] || exit 0
cd "$ROOT" 2>/dev/null || exit 0

# Keep the hook JSON (it carries `source`) for the marker step, without holding it in a variable.
INPUT_FILE="$(mktemp "${TMPDIR:-/tmp}/zoey-session.XXXXXX" 2>/dev/null || true)"
[ -n "$INPUT_FILE" ] && cat > "$INPUT_FILE" 2>/dev/null

TAB=$'\t'
EVENTS=""
emit() { EVENTS="${EVENTS}$1"$'\n'; }

AUTO_PULL="$(python3 "$PLUGIN/lib/zoey.py" get "$CFG" git.autoPull true 2>/dev/null)"
if [ $? -eq 2 ]; then
  emit "CFG_INVALID"
  AUTO_PULL=false
fi

# `compact` = the same session, context just got summarized: re-load the context only. No sync
# (files must not change under a running session) and no "new session" marker (it is not one).
SOURCE=""
[ -n "$INPUT_FILE" ] && SOURCE="$(python3 -c 'import json,sys
try: print(json.load(open(sys.argv[1])).get("source", ""))
except Exception: print("")' "$INPUT_FILE" 2>/dev/null)"
[ "$SOURCE" = compact ] && AUTO_PULL=false

# ---------- 1. sync ----------
if [ "$AUTO_PULL" != "false" ] && [ "$AUTO_PULL" != "0" ] && zoey_in_git "$ROOT"; then
  fetch_ok=1
  zoey_run_limited 8 git fetch --quiet 2>/dev/null
  frc=$?
  if [ "$frc" -eq 124 ]; then emit "FETCH_SLOW"; fetch_ok=0
  elif [ "$frc" -ne 0 ]; then emit "FETCH_FAILED"; fetch_ok=0
  fi

  upstream="$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)"
  if [ -n "$upstream" ]; then
    counts="$(git rev-list --left-right --count 'HEAD...@{upstream}' 2>/dev/null || true)"
    ahead="$(printf '%s' "$counts" | awk '{print $1}')"; behind="$(printf '%s' "$counts" | awk '{print $2}')"
    ahead="${ahead:-0}"; behind="${behind:-0}"
    # Tracked changes only: an untracked file (local tool config, build output) cannot be lost by
    # `pull --ff-only` - git refuses on its own if an incoming file would overwrite one, and that
    # surfaces as PULL_FAILED. Counting them would block the auto-pull forever on such a machine.
    dirty="$(git status --porcelain --untracked-files=no 2>/dev/null | head -1)"
    if [ "$behind" -gt 0 ]; then
      if [ -n "$dirty" ]; then
        emit "DIRTY${TAB}${behind}${TAB}${upstream}"
      elif [ "$ahead" -gt 0 ]; then
        emit "DIVERGED${TAB}${behind}${TAB}${upstream}"
      elif [ "$fetch_ok" -eq 0 ]; then
        emit "BEHIND_NO_PULL${TAB}${behind}${TAB}${upstream}"
      else
        zoey_run_limited 20 git pull --ff-only --quiet 2>/dev/null
        prc=$?
        case "$prc" in
          0)   emit "PULLED${TAB}${behind}${TAB}${upstream}" ;;
          124) emit "PULL_SLOW${TAB}${behind}${TAB}${upstream}" ;;
          *)   emit "PULL_FAILED${TAB}${behind}${TAB}${upstream}" ;;
        esac
      fi
    fi
    [ "$ahead" -gt 0 ] && emit "UNPUSHED${TAB}${ahead}"
  fi
fi

# ---------- 2. session marker (after the pull) ----------
if [ -n "$INPUT_FILE" ] && [ -s "$INPUT_FILE" ] && [ "$SOURCE" != compact ]; then
  python3 "$PLUGIN/lib/log_prompt.py" "$ROOT" "$CFG" "$PLUGIN/templates/i18n" < "$INPUT_FILE" 2>/dev/null
fi
[ -n "$INPUT_FILE" ] && rm -f "$INPUT_FILE"

# ---------- 3. context ----------
python3 "$PLUGIN/lib/session_start.py" "$ROOT" "$CFG" "$PLUGIN/templates/i18n" "$EVENTS" 2>/dev/null
exit 0
