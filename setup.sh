#!/usr/bin/env bash
# New machine: install all three - superpowers + ZoeyMemory + openspec CLI. Safe to re-run.
#
# Usage: bash setup.sh [ZoeyMemory marketplace source]
#   default source: tuandda98/ZoeyMemory (GitHub). Not pushed yet? Pass a local path, e.g.:
#   bash setup.sh ~/ZoeyMemory
set -uo pipefail

ZOEY_SRC="${1:-tuandda98/ZoeyMemory}"

command -v claude >/dev/null 2>&1 || { echo "ERROR: Claude Code CLI not found"; exit 1; }

echo "# 1/3 superpowers"
claude plugin marketplace add obra/superpowers-marketplace 2>&1 | tail -1
claude plugin install superpowers@superpowers-marketplace 2>&1 | tail -1

echo "# 2/3 ZoeyMemory ($ZOEY_SRC)"
claude plugin marketplace add "$ZOEY_SRC" 2>&1 | tail -1
claude plugin install zoey-memory@zoey-memory 2>&1 | tail -1

echo "# 3/3 openspec CLI"
if command -v openspec >/dev/null 2>&1; then
  echo "OK    openspec $(openspec --version) already installed"
elif command -v npm >/dev/null 2>&1; then
  npm i -g @fission-ai/openspec@latest >/dev/null 2>&1 && echo "OK    openspec $(openspec --version)" || echo "WARN  openspec install failed - needs Node 20.19+"
else
  echo "WARN  npm missing - install Node 20.19+ then: npm i -g @fission-ai/openspec@latest"
fi

echo
claude plugin list 2>/dev/null | grep -E "superpowers@|zoey-memory@" -A3
echo
echo "Done. Open a repo and run /zoey-memory:init to enable it there."
