#!/usr/bin/env bash
# SessionStart: SYNC then LOAD CONTEXT - two jobs, one hook, in the right order (pull FIRST, read AFTER).
#
# Job 1 - two-machine sync: fetch (8s ceiling); if behind origin AND the tree is CLEAN AND not
# diverged, `pull --ff-only` automatically; dirty tree or diverged -> only WARN; unpushed commits
# -> warn too.
# Job 2 - load context into the session start:
#   - the last N prompts the user sent (automatic journal)
#   - the latest entry of the session journal (written by /zoey-memory:handoff)
#   - open OpenSpec changes with task progress
#   - recent git log
#
# Why: Claude's memory does not travel across machines or sessions. Without this hook every new
# session re-asks what was already answered and re-proposes options already rejected.
#
# Toggle per repo via `.claude/zoey-memory.json` (`git.autoPull`, `context.enabled`). No config
# file = repo has not enabled ZoeyMemory -> exit silently. ALWAYS exit 0.
set -uo pipefail

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
CTX_ON="$(read_cfg context.enabled)"
N_PROMPTS="$(read_cfg context.recentPrompts)"; [ -n "$N_PROMPTS" ] || N_PROMPTS=30
FILE_PROMPTS="$(read_cfg journal.prompts)";   [ -n "$FILE_PROMPTS" ] || FILE_PROMPTS="docs/memory/PROMPTS.md"
FILE_SESSIONS="$(read_cfg journal.sessions)"; [ -n "$FILE_SESSIONS" ] || FILE_SESSIONS="docs/memory/SESSIONS.md"

SYNC_MSG=""
add_msg() { SYNC_MSG="${SYNC_MSG}$1"$'\n'; }

# ---------- JOB 1: sync ----------
if [ -d "$ROOT/.git" ] && [ "$AUTO_PULL" != "0" ]; then
  git fetch --quiet 2>/dev/null &
  fpid=$!; i=0
  while kill -0 "$fpid" 2>/dev/null && [ "$i" -lt 16 ]; do sleep 0.5; i=$((i + 1)); done
  if kill -0 "$fpid" 2>/dev/null; then
    kill "$fpid" 2>/dev/null; wait "$fpid" 2>/dev/null
    add_msg "WARNING: git fetch took over 8s (slow/offline network?) - the origin comparison below may be STALE."
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
        add_msg "OK: auto \`git pull --ff-only\` brought in $behind new commit(s) from $upstream (tree was clean, so it was safe). FILES ON DISK JUST CHANGED - anything you remember about this repo may be outdated."
      elif [ -n "$dirty" ]; then
        add_msg "WARNING: branch is BEHIND $upstream by $behind commit(s) but the working tree has UNCOMMITTED CHANGES, so no auto-pull. Settle the in-progress work (commit/stash) and \`git pull\` BEFORE continuing."
      else
        add_msg "WARNING: branch is BEHIND $upstream by $behind commit(s) and has DIVERGED (local commits not pushed). Needs a deliberate rebase/merge - ask the user before deciding."
      fi
    fi
    [ "${ahead:-0}" -gt 0 ] && add_msg "WARNING: $ahead commit(s) from the previous session are NOT PUSHED - \`git push\` soon or the other machine will not see them."
  fi
fi

# ---------- JOB 2: load context ----------
[ "$CTX_ON" = "0" ] && { [ -n "$SYNC_MSG" ] && printf '%s' "$SYNC_MSG"; exit 0; }

python3 - "$ROOT" "$FILE_PROMPTS" "$FILE_SESSIONS" "$N_PROMPTS" "$SYNC_MSG" <<'PY' 2>/dev/null || { [ -n "$SYNC_MSG" ] && printf '%s' "$SYNC_MSG"; exit 0; }
import json, os, re, subprocess, sys

root, p_rel, s_rel, n_prompts, sync_msg = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4] or 30), sys.argv[5]
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
    parts.append("## Two-machine sync\n" + sync_msg.strip())

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
    parts.append(
        f"## What the user asked recently (last {n_prompts}, source {p_rel})\n" + "\n".join(asks[-n_prompts:])
    )

# 2. Latest session note - what is in progress, why we stopped, who decides what.
blocks = [b.strip() for b in re.split(r"(?m)^(?=## )", read(os.path.join(root, s_rel))) if b.strip().startswith("## ")]
if blocks:
    parts.append(f"## Latest session note (source {s_rel})\n" + blocks[-1][:1500])

# 3. OpenSpec - open changes with progress.
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
        prog = f"{done}/{total} tasks done" if total else "no tasks yet"
        rows.append(f"- `{name}` - {prog} - present: {', '.join(arts) or 'empty'}")
    if rows:
        parts.append(
            "## OpenSpec - open changes (source openspec/changes/)\n" + "\n".join(rows)
            + "\n\nContinue: `/opsx:apply <name>` - all tasks done: `/opsx:archive <name>`."
        )
    else:
        parts.append("## OpenSpec\nNo open changes. New work worth remembering -> `/opsx:propose <name>`.")
elif not os.path.isdir(os_dir):
    parts.append("## OpenSpec\nOpenSpec is NOT initialized in this repo (no `openspec/`). Run `/zoey-memory:init`.")

# 4. Recent work.
log = sh("git", "log", "--oneline", "-8")
if log:
    branch = sh("git", "branch", "--show-current")
    parts.append(f"## Git - branch `{branch or '?'}`\n{log}")

if not parts:
    sys.exit(0)

ctx = (
    "# Context auto-loaded at session start (ZoeyMemory, hook session-start.sh)\n\n"
    "Read all of this BEFORE answering the first prompt. It is what happened in the previous "
    "session and/or ON THE OTHER MACHINE - do not re-ask what is already answered here, do not "
    "re-propose options already rejected. Division of labor: specs/decisions -> OpenSpec (/opsx:*) "
    "- TDD/debugging/verification/review -> superpowers - memory -> ZoeyMemory. Details in CLAUDE.md.\n\n"
    + "\n\n".join(parts)
)
print(json.dumps({
    "hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": ctx},
    "suppressOutput": True,
}))
PY
exit 0
