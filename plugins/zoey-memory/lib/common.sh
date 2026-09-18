# shellcheck shell=bash
# Shared shell helpers for ZoeyMemory hooks and scripts. Source it: . "$PLUGIN/lib/common.sh"
# bash 3.2 compatible (macOS default).

# Resolve the repo root the SAME way everywhere, so hooks and scripts agree:
#   1. the directory given as $1, if any
#   2. else $CLAUDE_PROJECT_DIR (the directory Claude Code was launched in), else the cwd
# ...and then the git top level of that directory, because Claude may be launched in a
# subdirectory of the repo while the config and journals live at the repo root.
# Falls back to the directory itself when it is not inside a git work tree.
zoey_resolve_root() {
  local start top
  start="${1:-${CLAUDE_PROJECT_DIR:-$PWD}}"
  top="$(git -C "$start" rev-parse --show-toplevel 2>/dev/null || true)"
  if [ -n "$top" ]; then
    printf '%s\n' "$top"
  else
    (cd "$start" 2>/dev/null && pwd)
  fi
}

# True when $1 (default cwd) is inside a git work tree. Works for worktrees and submodules,
# where `.git` is a file rather than a directory.
zoey_in_git() {
  git -C "${1:-.}" rev-parse --is-inside-work-tree >/dev/null 2>&1
}

# Run a command with a wall-clock limit (macOS has no `timeout`).
#   zoey_run_limited <seconds> cmd args...
# Returns the command's exit code, or 124 when it was killed for exceeding the limit.
zoey_run_limited() {
  local limit=$1 pid i=0 rc
  shift
  "$@" &
  pid=$!
  while kill -0 "$pid" 2>/dev/null && [ "$i" -lt $((limit * 2)) ]; do
    sleep 0.5
    i=$((i + 1))
  done
  if kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    return 124
  fi
  wait "$pid"
  rc=$?
  return $rc
}

# Look up an installed Claude Code plugin by name.
#   zoey_plugin_info <name>  ->  "<version>\t<enabled|disabled>\t<installPath>", or nothing if absent
zoey_plugin_info() {
  claude plugin list --json 2>/dev/null | python3 -c '
import json,sys
try: items=json.load(sys.stdin)
except Exception: items=[]
for p in items if isinstance(items,list) else []:
    if str(p.get("id","")).startswith(sys.argv[1]+"@"):
        print("%s\t%s\t%s" % (p.get("version","?"), "enabled" if p.get("enabled") else "disabled", p.get("installPath",""))); break
' "$1" 2>/dev/null
}
