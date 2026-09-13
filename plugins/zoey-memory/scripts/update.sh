#!/usr/bin/env bash
# Update all three tools on this machine: superpowers, ZoeyMemory, openspec CLI.
# If run inside a repo that has openspec/, also regenerates that repo's OpenSpec command files.
# Safe to re-run. Plugin updates need a Claude Code restart (or /reload-plugins) to take effect.
#
# Usage: bash update.sh
set -uo pipefail

command -v claude >/dev/null 2>&1 || { echo "ERROR: Claude Code CLI not found"; exit 1; }

echo "# 1/4 marketplaces"
claude plugin marketplace update 2>&1 | tail -3

echo "# 2/4 plugins"
claude plugin update superpowers@superpowers-marketplace 2>&1 | tail -1
claude plugin update zoey-memory@zoey-memory 2>&1 | tail -1

echo "# 3/4 openspec CLI"
if command -v npm >/dev/null 2>&1; then
  before="$(openspec --version 2>/dev/null || echo none)"
  npm i -g @fission-ai/openspec@latest >/dev/null 2>&1 && echo "OK    openspec $before -> $(openspec --version 2>/dev/null)" || echo "WARN  openspec install failed"
else
  echo "WARN  npm missing - cannot update openspec"
fi

echo "# 4/4 this repo"
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
if [ -d "$ROOT/openspec" ] && command -v openspec >/dev/null 2>&1; then
  (cd "$ROOT" && openspec update . 2>&1 | tail -2) && echo "OK    regenerated OpenSpec command files in $ROOT (commit .claude/commands and .claude/skills if they changed)"
else
  echo "..    no openspec/ in $ROOT - nothing to regenerate"
fi

echo
echo "Done. Restart Claude Code or run /reload-plugins, then run /zoey-memory:doctor to check for drift."
