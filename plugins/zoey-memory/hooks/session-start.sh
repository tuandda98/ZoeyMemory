#!/usr/bin/env bash
# SessionStart: SYNC then LOAD CONTEXT - two jobs, one hook, in the right order (pull FIRST, read AFTER).
#
# Job 1 - two-machine sync: fetch (8s ceiling); if behind origin AND the tree is CLEAN AND not
# diverged, `pull --ff-only` automatically; dirty tree or diverged -> only WARN; unpushed commits
# -> warn too. Bash emits machine-readable events; Python renders them in the configured language.
# Job 2 - load context into the session start:
#   - the last N prompts the user sent (automatic journal)
#   - the latest entry of the session journal (written by /zoey-memory:handoff)
#   - open OpenSpec changes with task progress (read from the filesystem, no CLI dependency)
#   - recent git log
#
# Why: Claude's memory does not travel across machines or sessions. Without this hook every new
# session re-asks what was already answered and re-proposes options already rejected.
#
# Toggle per repo via `.claude/zoey-memory.json` (`git.autoPull`, `context.enabled`). Language of
# the loaded text: `language` -> templates/i18n/<lang>.json (fallback en). No config file = repo has
# not enabled ZoeyMemory -> exit silently. ALWAYS exit 0.
set -uo pipefail

PLUGIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || true)}"
[ -n "$ROOT" ] || exit 0
CFG="$ROOT/.claude/zoey-memory.json"
[ -f "$CFG" ] || exit 0
cd "$ROOT" 2>/dev/null || exit 0

# ---------- read config (missing/broken -> safe defaults) ----------
read_cfg() { python3 -c "
import json,sys
try: c=json.load(open('$CFG'))
except Exception: c={}
cur=c
for k in '$1'.split('.'):
    cur=cur.get(k) if isinstance(cur,dict) else None
print('' if cur is None else ('1' if cur is True else ('0' if cur is False else cur)))
" 2>/dev/null; }

AUTO_PULL="$(read_cfg git.autoPull)"

# ---------- JOB 1: sync (emit events: FETCH_SLOW | PULLED|n|upstream | DIRTY|n|upstream | DIVERGED|n|upstream | UNPUSHED|n) ----------
EVENTS=""
emit() { EVENTS="${EVENTS}$1"$'\n'; }

if [ -d "$ROOT/.git" ] && [ "$AUTO_PULL" != "0" ]; then
  git fetch --quiet 2>/dev/null &
  fpid=$!; i=0
  while kill -0 "$fpid" 2>/dev/null && [ "$i" -lt 16 ]; do sleep 0.5; i=$((i + 1)); done
  if kill -0 "$fpid" 2>/dev/null; then
    kill "$fpid" 2>/dev/null; wait "$fpid" 2>/dev/null
    emit "FETCH_SLOW"
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
        emit "PULLED|$behind|$upstream"
      elif [ -n "$dirty" ]; then
        emit "DIRTY|$behind|$upstream"
      else
        emit "DIVERGED|$behind|$upstream"
      fi
    fi
    [ "${ahead:-0}" -gt 0 ] && emit "UNPUSHED|$ahead"
  fi
fi

# ---------- JOB 2: render sync events + load context ----------
python3 - "$ROOT" "$CFG" "$PLUGIN/templates/i18n" "$EVENTS" <<'PY' 2>/dev/null
import json, os, re, subprocess, sys

root, cfg_path, i18n_dir, events = sys.argv[1:5]

def load_json(path):
    try:
        return json.load(open(path, encoding="utf-8"))
    except Exception:
        return {}

def read(path):
    try:
        return open(path, encoding="utf-8").read()
    except Exception:
        return ""

def sh(*cmd):
    try:
        return subprocess.run(cmd, cwd=root, capture_output=True, text=True, timeout=10).stdout.strip()
    except Exception:
        return ""

cfg = load_json(cfg_path)
lang = str(cfg.get("language") or "en")
t = load_json(os.path.join(i18n_dir, "en.json"))
t.update(load_json(os.path.join(i18n_dir, lang + ".json")))

journal = cfg.get("journal") or {}
context = cfg.get("context") or {}
p_rel = journal.get("prompts") or "docs/memory/PROMPTS.md"
s_rel = journal.get("sessions") or "docs/memory/SESSIONS.md"
try:
    n_prompts = int(context.get("recentPrompts") or 30)
except Exception:
    n_prompts = 30
ctx_on = context.get("enabled") is not False

parts = []

# 0. Sync events -> localized messages.
sync_lines = []
for ev in events.splitlines():
    f = ev.split("|")
    if f[0] == "FETCH_SLOW":
        sync_lines.append(t["sync_fetch_slow"])
    elif f[0] in ("PULLED", "DIRTY", "DIVERGED") and len(f) == 3:
        sync_lines.append(t["sync_" + f[0].lower()].format(n=f[1], upstream=f[2]))
    elif f[0] == "UNPUSHED" and len(f) == 2:
        sync_lines.append(t["sync_unpushed"].format(n=f[1]))
if sync_lines:
    parts.append(t["sync_title"] + "\n" + "\n".join(sync_lines))

if not ctx_on:
    if sync_lines:
        print("\n".join(sync_lines))
    sys.exit(0)

# 1. What the user asked recently - drop machine-generated noise.
asks = []
for ln in read(os.path.join(root, p_rel)).splitlines():
    m = re.match(r"^- \[(\d{2}:\d{2})\] (.+)$", ln)
    if not m:
        continue
    txt = m.group(2).strip()
    if txt.startswith(("<task-notification>", "<system-reminder>", "<local-command", "<command-name>")):
        continue
    asks.append(f"[{m.group(1)}] {txt[:200]}")
if asks:
    parts.append(t["asks_title"].format(n=n_prompts, path=p_rel) + "\n" + "\n".join(asks[-n_prompts:]))

# 2. Latest session note.
blocks = [b.strip() for b in re.split(r"(?m)^(?=## )", read(os.path.join(root, s_rel))) if b.strip().startswith("## ")]
if blocks:
    parts.append(t["session_title"].format(path=s_rel) + "\n" + blocks[-1][:1500])

# 3. OpenSpec - open changes with progress (filesystem only, so it keeps working if the CLI changes).
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
        prog = t["tasks_done"].format(done=done, total=total) if total else t["no_tasks"]
        rows.append(t["openspec_row"].format(name=name, progress=prog, artifacts=", ".join(arts) or t["empty"]))
    if rows:
        parts.append(t["openspec_open_title"] + "\n" + "\n".join(rows) + "\n\n" + t["openspec_hint"])
    else:
        parts.append(t["openspec_none"])
elif not os.path.isdir(os_dir):
    parts.append(t["openspec_missing"])

# 4. Recent work.
log = sh("git", "log", "--oneline", "-8")
if log:
    branch = sh("git", "branch", "--show-current")
    parts.append(t["git_title"].format(branch=branch or "?") + "\n" + log)

if not parts:
    sys.exit(0)

ctx = t["ctx_title"] + "\n\n" + t["ctx_intro"] + "\n\n" + "\n\n".join(parts)
print(json.dumps({
    "hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": ctx},
    "suppressOutput": True,
}))
PY
exit 0
