#!/usr/bin/env bash
# SessionStart + UserPromptSubmit: AUTOMATIC JOURNAL - a session marker plus every prompt the user sends.
#
# This journal records the PATH ("what did the user ask, in what order"). Conclusions ("what got
# done, why we stopped") live in the session note written by /zoey-memory:handoff; the reasoning
# behind decisions lives in OpenSpec. This file is the only thing that survives a session that
# ends abruptly (crash, closed tab, dead battery).
#
# Target: `.claude/zoey-memory.json` -> `journal.prompts` (default docs/memory/PROMPTS.md). COMMITTED.
# Language of the written text: `language` in the config -> templates/i18n/<lang>.json (fallback en).
# No `.claude/zoey-memory.json` = repo has not enabled ZoeyMemory -> exit immediately, create nothing.
# ALWAYS exit 0: a broken journal must never block a working session.
set -uo pipefail

PLUGIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || true)}"
[ -n "$ROOT" ] || exit 0
CFG="$ROOT/.claude/zoey-memory.json"
[ -f "$CFG" ] || exit 0

INPUT=$(cat 2>/dev/null || true)
[ -n "$INPUT" ] || exit 0

STAMP=$(date '+%Y-%m-%d %H:%M')
TIME=$(date '+%H:%M')
BRANCH=$(git -C "$ROOT" branch --show-current 2>/dev/null || echo '?')

ZOEY_INPUT="$INPUT" python3 - "$ROOT" "$CFG" "$PLUGIN/templates/i18n" "$STAMP" "$TIME" "$BRANCH" <<'PY' 2>/dev/null
import json, os, sys

root, cfg_path, i18n_dir, stamp, time_, branch = sys.argv[1:7]

def load_json(path):
    try:
        return json.load(open(path, encoding="utf-8"))
    except Exception:
        return {}

cfg = load_json(cfg_path)
journal = cfg.get("journal") or {}
if journal.get("enabled") is False:
    sys.exit(0)
rel = journal.get("prompts") or "docs/memory/PROMPTS.md"
log = os.path.join(root, rel)

lang = str(cfg.get("language") or "en")
t = load_json(os.path.join(i18n_dir, "en.json"))
t.update(load_json(os.path.join(i18n_dir, lang + ".json")))

try:
    data = json.loads(os.environ.get("ZOEY_INPUT", ""))
except Exception:
    sys.exit(0)

event = data.get("hook_event_name", "")
if event == "SessionStart":
    line = t["new_session"].format(stamp=stamp, branch=branch, source=data.get("source", "?"))
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
        f.write(t["prompts_header"])
with open(log, "a", encoding="utf-8") as f:
    f.write(line)
PY
exit 0
