#!/usr/bin/env bash
# UserPromptSubmit: AUTOMATIC JOURNAL - append every prompt the user sends to docs/memory/PROMPTS.md.
# (The per-session marker is written by session-start.sh AFTER the git sync, so the journal is
# never dirty at pull time.)
#
# This journal records the PATH ("what did the user ask, in what order"). Conclusions live in the
# session note written by /zoey-memory:handoff; the reasoning behind decisions lives in OpenSpec.
# It is the only thing that survives a session that ends abruptly.
#
# Hook JSON is passed straight through on stdin (no shell buffering, so prompt size does not matter).
# No `.claude/zoey-memory.json` at the repo root = ZoeyMemory not enabled -> exit, create nothing.
# ALWAYS exit 0: a broken journal must never block a working session.
set -uo pipefail

PLUGIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$PLUGIN/lib/common.sh"

ROOT="$(zoey_resolve_root)"
[ -n "$ROOT" ] || exit 0
CFG="$ROOT/.claude/zoey-memory.json"
[ -f "$CFG" ] || exit 0

python3 "$PLUGIN/lib/log_prompt.py" "$ROOT" "$CFG" "$PLUGIN/templates/i18n" 2>/dev/null
exit 0
